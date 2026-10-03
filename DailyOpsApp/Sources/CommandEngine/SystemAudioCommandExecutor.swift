import Foundation
import CoreAudio
import AudioToolbox

/// Summary of audio volume information.
struct VolumeInfo: Equatable, Sendable {
    let volume: Float  // 0.0 to 1.0
    let isMuted: Bool
}

/// Abstract interface for system audio operations.
@MainActor
protocol SystemAudioControlling: Sendable {
    func getVolume() throws -> VolumeInfo
    func setVolume(_ volume: Float) throws
    func volumeUp() throws
    func volumeDown() throws
    func mute() throws
    func unmute() throws
}

/// Concrete System Audio controller using native macOS Core Audio APIs.
@MainActor
final class SystemAudioControl: SystemAudioControlling {
    private let defaultOutputDeviceID: AudioDeviceID

    init?() {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceID)
        guard status == noErr, deviceID != 0 else {
            return nil
        }
        self.defaultOutputDeviceID = deviceID
    }

    func getVolume() throws -> VolumeInfo {
        var volume: Float = 0.0
        var propertySize = UInt32(MemoryLayout<Float>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &propertySize, &volume)
        guard status == noErr else {
            throw CommandExecutionError.operationFailed("Failed to read volume.")
        }

        // Get mute state
        var isMuted: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let muteStatus = AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &propertySize, &isMuted)
        let muted = (muteStatus == noErr && isMuted != 0)

        return VolumeInfo(volume: volume, isMuted: muted)
    }

    func setVolume(_ volume: Float) throws {
        let clampedVolume = max(0.0, min(1.0, volume))
        let propertySize = UInt32(MemoryLayout<Float>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volumeToSet = clampedVolume
        let status = AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, propertySize, &volumeToSet)
        guard status == noErr else {
            throw CommandExecutionError.operationFailed("Failed to set volume.")
        }
    }

    func volumeUp() throws {
        let info = try getVolume()
        let increment: Float = 0.1 // 10 percentage points
        let newVolume = min(1.0, info.volume + increment)
        try setVolume(newVolume)
    }

    func volumeDown() throws {
        let info = try getVolume()
        let increment: Float = 0.1 // 10 percentage points
        let newVolume = max(0.0, info.volume - increment)
        try setVolume(newVolume)
    }

    func mute() throws {
        var muted: UInt32 = 1
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, propertySize, &muted)
        guard status == noErr else {
            throw CommandExecutionError.operationFailed("Failed to mute volume.")
        }
    }

    func unmute() throws {
        var muted: UInt32 = 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, propertySize, &muted)
        guard status == noErr else {
            throw CommandExecutionError.operationFailed("Failed to unmute volume.")
        }
    }
}

/// Fake System Audio controller for unit testing.
@MainActor
final class FakeSystemAudioControl: SystemAudioControlling {
    var volumeToReturn: Float = 0.5
    var mutedToReturn: Bool = false
    var shouldFail: Bool = false

    private(set) var setVolumeCalls: [Float] = []
    private(set) var volumeUpCalls: Int = 0
    private(set) var volumeDownCalls: Int = 0
    private(set) var muteCalls: Int = 0
    private(set) var unmuteCalls: Int = 0

    func getVolume() throws -> VolumeInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Volume unavailable.")
        }
        return VolumeInfo(volume: volumeToReturn, isMuted: mutedToReturn)
    }

    func setVolume(_ volume: Float) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to set volume.")
        }
        setVolumeCalls.append(volume)
    }

    func volumeUp() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to increase volume.")
        }
        volumeUpCalls += 1
    }

    func volumeDown() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to decrease volume.")
        }
        volumeDownCalls += 1
    }

    func mute() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to mute volume.")
        }
        muteCalls += 1
    }

    func unmute() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to unmute volume.")
        }
        unmuteCalls += 1
    }
}

/// Executes System Audio commands.
@MainActor
struct SystemAudioCommandExecutor: CommandExecuting {
    private let control: SystemAudioControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .systemVolumeUp,
        .systemVolumeDown,
        .systemVolumeSet,
        .systemVolumeMute,
        .systemVolumeUnmute,
        .systemVolumeGet
    ]

    init(control: SystemAudioControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .systemVolumeUp:
            try control.volumeUp()
            let info = try control.getVolume()
            return formatVolumeFeedback(info.volume, isMuted: info.isMuted, action: "increased")

        case .systemVolumeDown:
            try control.volumeDown()
            let info = try control.getVolume()
            return formatVolumeFeedback(info.volume, isMuted: info.isMuted, action: "decreased")

        case .systemVolumeSet:
            if case .systemVolumeSet(let percentage) = intent.arguments {
                try control.setVolume(Float(percentage) / 100.0)
                _ = try control.getVolume()
                return "Volume set to \(percentage)%."
            }
            throw CommandExecutionError.malformedArguments(intent.identifier)

        case .systemVolumeMute:
            try control.mute()
            return "Volume muted."

        case .systemVolumeUnmute:
            try control.unmute()
            return "Volume unmuted."

        case .systemVolumeGet:
            let info = try control.getVolume()
            let percentage = Int(info.volume * 100)
            if info.isMuted {
                return "Current volume is \(percentage)% (muted)."
            } else {
                return "Current volume is \(percentage)%."
            }

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }

    private func formatVolumeFeedback(_ volume: Float, isMuted: Bool, action: String) -> String {
        let percentage = Int(volume * 100)
        if isMuted {
            return "Volume \(action) to \(percentage)% (muted)."
        } else {
            return "Volume \(action) to \(percentage)%."
        }
    }
}