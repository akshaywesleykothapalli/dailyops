# Contributing to DailyOps

Thanks for your interest! DailyOps is a small, focused codebase — contributions that keep it that way are the most welcome.

## Development setup

1. Install Xcode 26+ and XcodeGen (`brew install xcodegen`)
2. `./scripts/install.sh` builds, signs, installs to /Applications, and launches
3. After adding/removing source files, re-run `xcodegen` (the `.xcodeproj` is generated; only `project.yml` is committed)

## Testing changes

- `DailyOps --selftest path/to/audio.wav` runs the full transcription + cleanup pipeline headlessly and prints timings.
- `DailyOps --show-hud` shows the pill overlay without dictating.
- End-to-end: hold Fn in any text field and speak.

## Things to know before touching the code

- **Swift 6 strict concurrency is on.** Audio-thread callbacks must be `@Sendable`; a plain closure formed in a `@MainActor` context inherits its isolation and will trap at runtime when CoreAudio invokes it.
- **macOS permission grants are tied to the code signature.** Rebuilds signed with a stable identity keep Accessibility/Microphone grants; ad-hoc builds lose them every time. The scripts handle this — avoid running from Xcode and from /Applications simultaneously (two instances fight over the hotkey).
- **The cleanup stage must never break dictation.** Every failure path (model unavailable, timeout, implausible output) falls back to the raw transcript. Keep it that way.

## Pull requests

- One focused change per PR
- Match the existing code style; comments explain constraints, not mechanics
- Verify with `--selftest` plus a real end-to-end dictation before submitting
