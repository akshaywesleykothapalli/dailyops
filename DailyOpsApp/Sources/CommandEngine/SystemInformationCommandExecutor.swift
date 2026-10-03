import Foundation
import IOKit.ps
import IOKit

/// Summary of battery information.
struct BatteryInfo: Equatable, Sendable {
    let percentage: Int?
    let isCharging: Bool
    let isFullyCharged: Bool
    let timeRemaining: TimeInterval?
    let isACPowered: Bool
}

/// Summary of macOS version information.
struct MacOSVersionInfo: Equatable, Sendable {
    let versionString: String
    let buildVersion: String?
}

/// Time information.
struct TimeInfo: Equatable, Sendable {
    let formattedTime: String
}

/// Date information.
struct DateInfo: Equatable, Sendable {
    let formattedDate: String
}

/// Abstract interface for system information operations.
@MainActor
protocol SystemInformationControlling: Sendable {
    func getBatteryInfo() throws -> BatteryInfo
    func getMacOSVersion() throws -> MacOSVersionInfo
    func getCurrentTime() throws -> TimeInfo
    func getCurrentDate() throws -> DateInfo
}

/// Concrete System Information controller using native macOS APIs.
@MainActor
final class SystemSystemInformationControl: SystemInformationControlling {
    func getBatteryInfo() throws -> BatteryInfo {
        // Use IOKit to get battery information
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

        guard let source = sources.first else {
            return BatteryInfo(
                percentage: nil,
                isCharging: false,
                isFullyCharged: false,
                timeRemaining: nil,
                isACPowered: false
            )
        }

        let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as! [String: Any]

        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 1
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isFullyCharged = currentCapacity >= maxCapacity
        let isACPowered = description[kIOPSPowerSourceStateKey] as? String == "AC Power"
        let timeRemaining = description[kIOPSTimeToEmptyKey] as? Int
        let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int

        let percentage = maxCapacity > 0 ? Int(Double(currentCapacity) / Double(maxCapacity) * 100) : nil

        var timeRemainingInterval: TimeInterval?
        if isCharging && timeToFull != nil && timeToFull != -1 {
            timeRemainingInterval = TimeInterval(timeToFull! * 60)
        } else if !isCharging && timeRemaining != nil && timeRemaining != -1 {
            timeRemainingInterval = TimeInterval(timeRemaining! * 60)
        }

        return BatteryInfo(
            percentage: percentage,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            timeRemaining: timeRemainingInterval,
            isACPowered: isACPowered
        )
    }

    func getMacOSVersion() throws -> MacOSVersionInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let buildVersion = ProcessInfo.processInfo.operatingSystemVersionString

        return MacOSVersionInfo(
            versionString: versionString,
            buildVersion: buildVersion
        )
    }

    func getCurrentTime() throws -> TimeInfo {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let formattedTime = formatter.string(from: Date())

        return TimeInfo(formattedTime: formattedTime)
    }

    func getCurrentDate() throws -> DateInfo {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        let formattedDate = formatter.string(from: Date())

        return DateInfo(formattedDate: formattedDate)
    }
}

/// Fake System Information controller for unit testing.
@MainActor
final class FakeSystemInformationControl: SystemInformationControlling {
    var batteryInfoToReturn: BatteryInfo?
    var macOSVersionToReturn: MacOSVersionInfo?
    var timeToReturn: TimeInfo?
    var dateToReturn: DateInfo?
    var shouldFail: Bool = false

    func getBatteryInfo() throws -> BatteryInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Battery information unavailable.")
        }
        return batteryInfoToReturn ?? BatteryInfo(percentage: nil, isCharging: false, isFullyCharged: false, timeRemaining: nil, isACPowered: false)
    }

    func getMacOSVersion() throws -> MacOSVersionInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("macOS version unavailable.")
        }
        return macOSVersionToReturn ?? MacOSVersionInfo(versionString: "macOS 26.0", buildVersion: "26A000")
    }

    func getCurrentTime() throws -> TimeInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Time unavailable.")
        }
        return timeToReturn ?? TimeInfo(formattedTime: "12:00 PM")
    }

    func getCurrentDate() throws -> DateInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Date unavailable.")
        }
        return dateToReturn ?? DateInfo(formattedDate: "Monday, January 1, 2024")
    }
}

/// Executes System Information commands.
@MainActor
struct SystemInformationCommandExecutor: CommandExecuting {
    private let control: SystemInformationControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .systemBattery,
        .systemMacOSVersion,
        .systemTime,
        .systemDate
    ]

    init(control: SystemInformationControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .systemBattery:
            let info = try control.getBatteryInfo()
            return formatBatteryInfo(info)

        case .systemMacOSVersion:
            let info = try control.getMacOSVersion()
            return formatMacOSVersion(info)

        case .systemTime:
            let info = try control.getCurrentTime()
            return formatTime(info)

        case .systemDate:
            let info = try control.getCurrentDate()
            return formatDate(info)

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }

    private func formatBatteryInfo(_ info: BatteryInfo) -> String {
        if info.isACPowered && info.percentage == 100 {
            return "Battery: 100%, fully charged."
        }

        if let percentage = info.percentage {
            var status = ""
            if info.isCharging {
                status = "charging"
            } else if info.isACPowered {
                status = "not charging (on AC power)"
            } else {
                status = "discharging"
            }

            if let timeRemaining = info.timeRemaining {
                let hours = Int(timeRemaining / 3600)
                let minutes = Int((timeRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
                if hours > 0 {
                    return "Battery: \(percentage)%, \(status), \(hours)h \(minutes)m remaining."
                } else {
                    return "Battery: \(percentage)%, \(status), \(minutes)m remaining."
                }
            } else {
                return "Battery: \(percentage)%, \(status)."
            }
        } else {
            return "Battery information is unavailable."
        }
    }

    private func formatMacOSVersion(_ info: MacOSVersionInfo) -> String {
        if let build = info.buildVersion {
            return "\(info.versionString) (\(build))"
        }
        return info.versionString
    }

    private func formatTime(_ info: TimeInfo) -> String {
        return "Current time: \(info.formattedTime)."
    }

    private func formatDate(_ info: DateInfo) -> String {
        return "Today's date: \(info.formattedDate)."
    }
}