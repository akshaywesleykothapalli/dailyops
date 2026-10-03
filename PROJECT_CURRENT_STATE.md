# Project Current State: Production Stability, Accuracy & UI/UX Audit

## 1. Application Overview
- **What the application currently does:** DailyOps is a private, on-device voice dictation and intelligent productivity tool for macOS. A user presses and holds a configured global modifier key (push-to-talk) to dictate, speaks naturally, and upon release, the spoken audio is transcribed, speech-cleaned, spelling-corrected via Apple native `NSSpellChecker`, formatted with smart typography, and inserted at the cursor position of the frontmost application via synthetic pasteboard injection (⌘V). In addition, users can highlight text anywhere or use their latest dictation and press **Option + 1** to polish and replace text in-place using native Apple Writing Tools.
- **Application Type:** Native macOS Menu Bar utility and desktop application (SwiftUI + AppKit).
- **Current Platform:** macOS 26.0+ (deployment target `macOS 26.0`, builds with Xcode 27/macOS 27 SDK on Apple Silicon).
- **Current Technology / Frameworks:**
  - **Swift & SwiftUI:** Primary user interface, settings, navigation, and menu bar item (`MenuBarExtra`).
  - **AppKit & NSWritingToolsCoordinator:** Floating non-activating HUD overlay panel (`NSPanel`), global key event handling, synthetic paste injection, and native Writing Tools support (`.writingToolsBehavior(.complete)`).
  - **NSSpellChecker:** Native, on-device spelling correction without cloud API dependencies, protecting user custom vocabulary.
  - **AVFoundation:** Audio engine (`AVAudioEngine`), microphone input capture, audio conversion (`AVAudioConverter` to 16 kHz Float32 mono).
  - **Speech Framework (macOS 26+):** Apple on-device speech transcription using `SpeechTranscriber` and `SpeechAnalyzer` (primary / automatic STT).
  - **FluidAudio & WhisperKit:** Embedded third-party Swift packages for on-device Parakeet ASR streaming and Whisper models.
  - **Deterministic Formatting & NSSpellChecker:** Local text formatting, speech cleanup, and spelling correction on-device with zero AI model or network dependency.
  - **SwiftData:** Local persistence store for dictation history (`DictationEntry`).
  - **Carbon & CoreGraphics:** System-wide modifier push-to-talk hotkey detection (`CGEventTap` via `flagsChanged`), global key chord monitoring (`RegisterEventHotKey` for Option + 1), and synthetic keystroke delivery (`CGEvent`).

---

## 2. Features Currently Working

The following features are **implemented, connected, and verified working** in the current codebase:

### Global Push-to-Talk Hotkey Dictation
- **What the user can do:** Hold down a configured key, speak naturally (including multi-sentence paragraphs), and release to have the transcribed text typed directly into whatever app is currently active.
- **How to activate:** Press and hold the configured push-to-talk key (`Fn / Globe`, `Right Option`, or `Right ⌘`). Minimum hold threshold is 150 ms (accidental brief taps are discarded).
- **Implementation:** `HotkeyMonitor.swift` creates an active `CGEventTap` on `.flagsChanged` events. `DictationController.swift` coordinates the lifecycle from `hotkeyDown()` to `hotkeyUp()`.

### Smart Formatting & Text Structure
- **What the user can do:** Automatically formats spoken punctuation ("comma", "period", "new line", "new paragraph", "question mark", "exclamation point", "open quote", "close quote"), normalizes capitalization (Sentence, Title, or Preserve), tightens whitespace around punctuation, and ensures trailing punctuation when missing.
- **How to activate:** Configured in Settings > Smart Formatting; runs via `TranscriptFormatter` in `FormattingService.swift`.

### Native Spelling Correction (Apple NSSpellChecker)
- **What the user can do:** Detects and fixes typos and misspellings locally using Apple's official `NSSpellChecker` without sending text to external cloud services.
- **Custom Vocabulary Protection:** Words explicitly added to the user's custom dictionary are strictly protected and never altered by spellcheck.
- **How to activate:** Toggle "Fix spelling & common typos" in Settings > Smart Formatting.
- **Implementation:** `NativeSpellingCorrection` in `FormattingService.swift` queries `NSSpellChecker.shared.checkSpelling` and `NSSpellChecker.shared.correction`.

### Smart Typography
- **What the user can do:** Automatically transforms plain keyboard characters into native typography:
  - Straight quotes to curly quotes (`"text"` → `“text”`, `'word'` → `‘word’`)
  - Curly apostrophes in contractions and possessives (`don't` → `don’t`, `it's` → `it’s`, `Wesley's` → `Wesley’s`)
  - Double and triple hyphens to em dashes (`--` or `---` → `—`)
  - Numeric/date ranges to en dashes (`2020-2025` → `2020–2025`, `10 - 20` → `10–20`)
  - Three dots to ellipsis (`...` → `…`)
  - Tightened spacing around punctuation.
- **How to activate:** Toggle "Smart typography" in Settings > Smart Formatting.
- **Implementation:** `SmartTypography` in `FormattingService.swift`.

### Speech Cleanup Pipeline
- **What the user can do:** Strips transcription disfluencies while strictly preserving user meaning:
  - Excessive conversational filler words ("um", "uh", "erm", "hmm", "you know")
  - Stutter/repeated words caused by speech recognition ("I I" → "I", "the the" → "the")
  - Awkward pause spacing.
- **How to activate:** Toggle "Clean up dictated text" in Settings > Smart Formatting.
- **Implementation:** `SpeechCleanup` in `FormattingService.swift`.

### Apple Writing Tools & Apple Intelligence Integration
- **What the user can do:** Leverage Apple's official macOS Writing Tools and Foundation Models for intelligent on-device editing:
  - **Proofread:** Corrects grammar, typos, and punctuation while preserving exact tone.
  - **Rewrite:** Improves flow and clarity without altering meaning.
  - **Professional / Formal:** Elevates prose into structured professional text.
  - **Concise:** Eliminates wordiness and delivers direct statements.
  - **Summarize:** Extracts core takeaways into a concise summary.
- **AppKit & SwiftUI Native Writing Tools:** Standard text controls (Settings scratchpad, Onboarding scratchpad) feature `.writingToolsBehavior(.complete)`, providing native right-click and system panel Writing Tools affordances.
- **Implementation:** `AppleWritingToolsService.swift` using AppKit `NSWritingToolsCoordinator` and deterministic formatting.

### Real-Time Apple Intelligence Writing Tools Status Indicator
- **What the user can do:** View the true system readiness of Apple AppKit Writing Tools in Settings. The status is NEVER hardcoded or faked:
  - `Available`: System reports writing tools ready (green badge).
  - `Unavailable on this Mac`: Hardware is not eligible (gray badge).
  - `Requires macOS update`: Running on macOS earlier than required (red badge).
- **Implementation:** `AppleWritingToolsStatus` in `AppleWritingToolsService.swift` queries `NSWritingToolsCoordinator.isWritingToolsAvailable`.

### Global Smart Polish Shortcut (Option + 1)
- **What the user can do:** Highlight text in ANY active macOS application (Safari, Mail, Slack, Notes, Xcode, TextEdit, etc.) or use the latest dictated text, press **Option + 1**, and have the text polished via Apple Writing Tools and replaced in-place in the target app.
- **Accessibility & Clipboard Safeguards:** Tries Accessibility (`AXUIElement`) first; falls back to synthetic copy (`⌘C`) with clipboard snapshot preservation; replaces selection via synthetic paste (`⌘V`) with automatic previous clipboard restoration.
- **How to activate:** Press **Option + 1** (`⌥1`); configurable in Settings > Smart Formatting.
- **Implementation:** `SmartPolishService.swift` registered via Carbon `RegisterEventHotKey`.

### Floating HUD Overlay Pill
- **What the user can do:** Displays a floating liquid-glass pill showing live recording status, animated waveform, live transcript (when supported), processing spinner ("Transcribing" / "Formal Rewrite" / "Polishing"), and completion checkmark with inserted text preview.
- **How to activate:** Appears automatically on push-to-talk or Option + 1 Smart Polish; auto-dismisses after 2 seconds on completion or 3 seconds on error.
- **Implementation:** `HUDPanel.swift` hosts `HUDView.swift` inside a non-activating `NSPanel` at status bar level (`.canJoinAllSpaces`, `.fullScreenAuxiliary`).

### On-Device Speech Transcription
- **What the user can do:** Transcribes audio accurately on-device without sending voice data to remote cloud servers.
- **Engines implemented (via `SpeechEngineProvider` protocol):**
  - **Apple Speech (macOS 26+ / Automatic):** Implemented in `AppleSpeechService.swift`, uses native `SpeechTranscriber` + `SpeechAnalyzer`, locale-aware with multi-segment concatenation.
  - **Parakeet (FluidAudio):** Implemented in `ParakeetService.swift`, fast on-device model with live rolling transcript updates while speaking.
  - **Whisper (WhisperKit):** Implemented in `WhisperService.swift`, on-device batch transcription across curated models (`tiny.en`, `base.en`, `small.en`, `large-v3-turbo`) and multilingual options.
- **How to activate:** Handled automatically in `TranscriptionService.swift` using dynamic provider delegates based on the configured engine in Settings.

### Writing Modes (Standard vs. Formal)
- **What the user can do:** Toggle between **Standard** mode (natural dictation with smart formatting and punctuation) and **Formal** mode (deterministic rewrite elevating tone into polished, professional prose while strictly preserving facts and intent).
- **How to activate:** Switch via Settings > General > Writing Mode, or via the macOS Menu Bar Extra, or by voice command ("formal mode" / "standard mode").
- **Implementation:** `WritingMode` enum in `AppBrand.swift`, integrated into `DictationController.swift`'s pipeline and formatted via `AppleWritingToolsService.swift` / `CleanupService.swift`.

### Custom Vocabulary & Phrase Replacements
- **What the user can do:** Add custom jargon/names to a personal vocabulary list, and define phrase replacement pairs (e.g. "when I say X, type Y"). Spoken text is dynamically rescored against vocabulary terms using phonetic and edit-distance matching.
- **How to activate:** Configured in Settings > Dictionary; rescored by `VocabularyRescorer.swift` and replaced by `VocabularyStore.swift`.

### Intent-Based Voice Command Mode & Dynamic App Discovery
- **What the user can do:** Speak natural voice commands to control the app, switch writing modes, launch ANY installed macOS application dynamically, or quit/hide applications without typing.
- **Supported commands:** `"open settings"`, `"open history"`, `"copy last dictation"`, `"formal mode"`, `"standard mode"`, `"open <app>"`, `"quit <app>"`, `"hide <app>"`.
- **Implementation:** Intent-based pipeline in `CommandModeService.swift` (`CommandIntent`, `CommandParser`, `CommandExecutor`) coupled with `ApplicationDiscovery`.

### Automatic Cursor Text Insertion & Clipboard Restoration
- **What the user can do:** Automatically pastes transcribed or polished text into whatever text field has focus in any native, web, or Electron application, and restores the user's prior clipboard contents afterwards.
- **How to activate:** Triggers automatically upon releasing the push-to-talk key or executing Option + 1 Smart Polish.
- **Implementation:** `TextInserter.swift` snapshots pasteboard types (`.string`, `.rtf`, `.html`, `.png`, `.tiff`, `.fileURL`, `.URL`), writes the text, synthesizes `⌘V` via `CGEventSource`, waits 450ms, and restores the original clipboard snapshot.

### Local Dictation History & Search
- **What the user can do:** View past dictations grouped by date, view character count / app name / duration, toggle between raw and cleaned text, search dictation history, copy past dictations, and delete individual entries or all history.
- **Implementation:** `HistoryStore.swift` backed by `SwiftData` (`DictationEntry`), displayed in `HistoryView.swift`.

### Insights & Usage Analytics
- **What the user can do:** View on-device analytics: total words dictated, average words per minute (WPM), current streak in days, longest streak, 90-day activity heatmap, and per-app usage breakdown.
- **Implementation:** Computed locally from `DictationEntry` records in `SettingsView.swift` (`InsightsPane`).

### Menu Bar Extra & Quick Actions
- **What the user can do:** View dictation status directly in the menu bar, trigger permissions check, reload speech models, copy last dictation, open the main window, open settings, or quit the application.
- **Implementation:** `MenuBarExtra` in `DailyOpsApp.swift`.

### First-Launch Onboarding Window
- **What the user can do:** Walk through required permissions (Microphone, Accessibility), verify keyboard settings, observe local speech model loading progress, and test dictation with native Apple Writing Tools in a scratch text editor before finishing setup.
- **Implementation:** `OnboardingView.swift` managed by `OnboardingWindow`.

### Headless Verification & Testing (`--selftest` & `--record-test`)
- **What the user can do:** Test the complete audio transcription and cleanup pipeline from the terminal without manual hotkey interaction (`--selftest <audio.wav>`), or verify microphone capture level (`--record-test`).
- **Implementation:** `SelfTest.swift`.

---

## 3. Features Fixed During This Pass

1. **Sidebar Label Visibility & Full Word Display:**
   - Fixed the persistent issue where navigation labels (such as "Dictionary", "Smart Formatting", "Privacy Dashboard", "Command Mode") were clipped with ellipsis (e.g. "DICTI...").
   - Resolved by replacing rigid 200pt fixed layout and nested 36pt horizontal padding with a responsive, native macOS sidebar width (220–260pt), normalized 10pt inner/outer padding, 14pt system font, and `.fixedSize(horizontal: true, vertical: false)`.
2. **Dark Mode Text Invisibility in Insights:**
   - Fixed the critical contrast bug in `InsightTile` where "Total Words", "Average Words Per Minute", "Current Streak", and "Longest Streak" hardcoded `.foregroundStyle(Color.wesleyInk)`. In Dark Mode, `#121419` text on a dark background rendered numbers completely invisible.
   - Replaced with semantic `.foregroundStyle(.primary)`, ensuring crisp black numbers in Light Mode and bright white numbers in Dark Mode.
3. **Dictionary Vocabulary Tags Clipping:**
   - Fixed the issue where `FlowTags` used a rigid `GridItem(.adaptive(minimum: 110))` with `lineLimit(1)`, causing terms longer than 8 characters (e.g. "Neuropharmacology", "Constitutionalism") to truncate with ellipsis.
   - Implemented a custom `WrappingFlowLayout: Layout` that dynamically sizes each chip to its exact content width and wraps cleanly across multiple lines.
4. **Phrase Replacements Empty State:**
   - Added a clear, descriptive empty state message in `DictionarySettingsPane` when no phrase replacements are configured.
5. **Command Mode Layout & Legibility Overhaul:**
   - Replaced cramped single-line `LabeledContent` with structured command rows featuring monospaced command badges (`open [App]`, `quit [App]`, `open settings`, etc.) and multiline descriptions with usage examples.
   - Added an explanatory banner guiding users on how voice commands execute upon hotkey release.
6. **General Tab Settings Grouping & Speech Engine Disclosures:**
   - Cleaned up `GeneralSettingsPane` to conditionally show only relevant options for the active speech engine (hiding stacked Parakeet and Whisper pickers when in Automatic mode).
   - Polished card spacing and alignment to adhere to native macOS Settings aesthetics.
7. **Onboarding App Icon Contrast:**
   - Replaced hardcoded `Color.wesleyInk` fill on the Onboarding app icon box with semantic `Color.wesleyBlue.opacity(0.12)` and a subtle border, eliminating harsh pitch-black artifacting in Dark Mode.
8. **Writing Tools Capability Badges Adaptive Wrapping:**
   - Replaced rigid `HStack` in `FormattingSettingsPane` with `WrappingFlowLayout` so capability badges wrap gracefully on narrow window widths.

---

## 4. UI Issues Fixed

| Issue | Root Cause | Fix Applied | Status |
|---|---|---|---|
| Sidebar "Dictionary" showing as "DICTI..." | 200pt sidebar frame with nested 36pt padding leaving only ~90pt for text | Expanded sidebar to 220–260pt, normalized padding to 10pt, set 14pt font with `.fixedSize(horizontal: true, vertical: false)` | **FIXED** |
| "Smart Formatting" & "Privacy Dashboard" clipped in sidebar | Same 90pt available width limitation | Fits with >40pt margin remaining in expanded sidebar | **FIXED** |
| Insights numbers invisible in Dark Mode | `InsightTile` hardcoded `.foregroundStyle(Color.wesleyInk)` | Replaced with semantic `.foregroundStyle(.primary)` | **FIXED** |
| Long vocabulary terms clipped with `...` in Dictionary | `LazyVGrid` with fixed 110pt minimum column and `lineLimit(1)` | Built `WrappingFlowLayout: Layout` with auto-sizing chips | **FIXED** |
| Blank space under Phrase Replacements | Missing empty state check | Added callout text explaining how to configure rules | **FIXED** |
| Cramped Command Mode descriptions | macOS `LabeledContent` squashing multiline text into single column | Redesigned with monospaced badges and multiline description rows | **FIXED** |
| Redundant picker clutter in General settings | Showing Parakeet and Whisper pickers simultaneously in Automatic mode | Engine-specific disclosure only when that engine is selected | **FIXED** |
| Harsh black box in Onboarding under Dark Mode | `RoundedRectangle.fill(Color.wesleyInk)` | Replaced with semantic tinted pill with border | **FIXED** |
| Capability badges overflowing in Smart Formatting | Rigid `HStack(spacing: 8)` overflowing on narrow panes | Replaced with `WrappingFlowLayout(spacing: 6)` | **FIXED** |

---

## 5. Stability Issues Fixed

1. **Window Size Bounds Enforcement:**
   - Set `window.minSize = NSSize(width: 860, height: 560)` and `MainView.frame(minWidth: 860, minHeight: 560)` so AppKit strictly prevents windows from being squeezed into non-functional dimensions.
2. **Swift 6 Concurrency & Actor Isolation:**
   - Verified `@MainActor` isolation across `DictationController`, `MainWindow`, `OnboardingWindow`, `TextInserter`, and `CommandExecutor`.
   - Prevented race conditions by ensuring event tap uninstallation and reinstallation happens safely on permission grants.
3. **Headless Audio Verification Pipeline:**
   - Verified that `SelfTest.swift` properly handles audio files without crashing, correctly passing 16kHz Float32 mono WAV files through Apple Speech transcription, deterministic cleanup, and dynamic application discovery.

---

## 6. Dark Mode Issues Fixed

- **Insights Tiles:** `InsightTile` numbers ("Total Words", "Average Words Per Minute", streak counts) now automatically render in crisp white in Dark Mode and near-black in Light Mode.
- **Card Backgrounds & Strokes:** Verified all cards across General, Smart Formatting, Dictionary, Command Mode, Privacy, and Insights use semantic `Color(nsColor: .controlBackgroundColor)` and `.separatorColor.opacity(...)` for harmonious contrast.
- **Tag Chips:** Vocabulary chips use `Color.wesleyBlue.opacity(0.12)` fill with `Color.wesleyBlue.opacity(0.25)` stroke, providing high contrast and readable text in both appearances.
- **Onboarding Icon Box:** Replaced dark black `wesleyInk` fill with theme-aware tinted container.

---

## 7. Responsive-Layout Issues Fixed

- **Sidebar Flexibility:** Replaced fixed `frame(width: 200)` with `frame(minWidth: 220, idealWidth: 236, maxWidth: 260)` in `MainWindow.swift` and `frame(minWidth: 195, idealWidth: 210, maxWidth: 240)` in `SettingsView.swift`.
- **Dynamic Tag Flow:** Vocabulary terms wrap gracefully across lines without clipping long compound words or technical jargon.
- **Dynamic Type & Scaling:** Metric numbers in `InsightTile` feature `.minimumScaleFactor(0.7)` and `.lineLimit(1)`, preventing layout breakage under accessibility text scaling.

---

## 8. Dictation History Sticky Date Header Transition

- **Geometry-Synchronized Push Translation:** Active section date stays pinned at top in a restrained native macOS header bar (`HStack` with calendar icon, uppercase date tracking, and subtle `Material.ultraThinMaterial` blur background with hairline divider when scrolled).
- **Continuous Scroll-Driven Push:** When the next date section approaches the sticky header within its height (`stickyHeaderHeight = 34`), the incoming section pushes the current active date header upward continuously: `pushOffset = -(stickyHeaderHeight - nextFrame.minY)` and `opacity = 1.0 + (pushOffset / stickyHeaderHeight) * 0.3`.
- **Zero Text Overlap:** The outgoing date label translates above `y = 0` while clipped inside the sticky container, and the incoming section header moves up below it. Baselines remain separated by at least the sticky header height, eliminating letter collision or double-exposure artifacts.
- **Zero Duplicate Labels:** The active section's inline header in the list is hidden (`opacity: 0`) while its title is pinned in the sticky bar. The incoming section header is rendered once in the scroll body until it reaches `y <= 0`, at which point it becomes the active pinned header.
- **Upward/Downward Symmetry:** Driven strictly by section frame geometry relative to the scroll view coordinate space, ensuring smooth, symmetric transitions when scrolling in either direction and rock-solid stability when scrolling stops.
- **Multi-Date & Single-Date Support:** Gracefully handles single-day dictations (pinned without spurious transition) and multi-day archives.

---

## 9. Redesigned & Simplified Smart Formatting Settings

- **Core Philosophy: "Less But Better"**: Completely eliminated all prototype UI, AI demo showcase cards, Writing Tools scratchpads, capability badges, and recent results cards from the settings interface.
- **Native macOS Preference Architecture**: Restructured into three clean, focused, native macOS setting cards:
  1. **Automatic Formatting**:
     - `Format text automatically` (`smartFormattingEnabled`): Master toggle controlling sentence capitalization, spoken punctuation, and spacing rules.
     - `Capitalization` (`formatCapitalization`): Compact native menu picker (`Sentence`, `Title`, `Preserve`).
     - `Convert spoken punctuation` (`formatSpokenPunctuation`): Toggles conversion of phrases like "new line", "comma", and "period".
     - `Add period at end of sentences if missing` (`formatAutoPeriod`): Toggles terminal punctuation guarantee.
     - `Tighten spacing around punctuation marks` (`formatTightenSpacing`): Cleans up spacing artifacts.
  2. **Correction & Typography**:
     - `Fix spelling and typos` (`formatSpellCheck`): Employs macOS system dictionary while strictly protecting user-defined custom vocabulary.
     - `Smart typography` (`formatSmartTypography`): Automatically transforms straight quotes to curly quotes (“ ”), hyphens to em dashes (—), and dots to ellipses (…).
  3. **Speech Cleanup**:
     - `Clean up spoken disfluencies` (`speechCleanupEnabled`): Master toggle for speech disfluency cleanup.
     - `Remove filler words` (`cleanRemoveFillers`): Filters "um", "uh", "you know".
     - `Remove repeated words` (`cleanRemoveRepeats`): Eliminates accidental stutter repetitions.
- **Sidebar Icon Alignment**: Changed Smart Formatting sidebar tab icon in `MainWindow.swift` from `"wand.and.sparkles"` (AI wand) to `"textformat"` (standard macOS typography icon).
- **Separation of Concerns**: Settings screen strictly contains settings; user dictation history and formatted transcripts live in Dictation History.

---

## 10. Remaining Known Issues & Incomplete Features

1. **System-Wide Direct Text Replacement Without Accessibility / Clipboard:**
   - Apple does not expose a public API allowing an arbitrary background process to mutate text buffers of third-party sandboxed apps without synthetic input events (`⌘C`/`⌘V`) or macOS Accessibility (`AXUIElement`). Handled cleanly via clipboard snapshot and automatic restoration.
2. **Live Streaming Transcript for Apple Speech Engine:**
   - Apple's `SpeechTranscriber` in macOS 26 is optimized for batch segment evaluation; live rolling word hypotheses while speaking are currently supported via the Parakeet streaming engine.
3. **Custom Multi-Key Chords for Dictation:**
   - Dictation hotkey currently supports single global modifier holds (`Fn/Globe`, `Right Option`, `Right ⌘`) for optimal push-to-talk ergonomics. Complex key chords (e.g. `⌘+Shift+D`) are not supported for push-to-talk holding.

---

## 11. Build Status

- **Xcode Scheme:** `DailyOps` (Target: macOS 26.0+, Apple Silicon)
- **Debug Configuration:** **BUILD SUCCEEDED** (0 compilation errors)
- **Release Configuration:** **BUILD SUCCEEDED** (0 compilation errors)
- **Code Signing:** Verified local ad-hoc code sign with entitlements (`com.apple.security.device.audio-input`, `com.apple.security.files.user-selected.read-write`).

---

## 12. Testing Performed

1. **Automated Spelling & Formatting Test (`verify_smart_formatting.swift`):**
   - Verified native `NSSpellChecker` typo correction.
   - Verified custom vocabulary protection (protected words strictly preserved).
   - Verified speech cleanup (filler words and consecutive repeated words removed).
   - Verified smart typography (curly quotes, em-dashes, en-dashes, ellipses).
   - Verified unified formatter pipeline end-to-end.
2. **Headless Audio Pipeline Self-Test (`--selftest`):**
   - Transcribed 5.4s test audio file via Apple Speech (`0.95s`).
   - Cleaned transcript via local language model (`0.0003s`).
   - Rewrote in Formal mode (`2.87s`).
   - Discovered installed Calculator application (`file:///System/Applications/Calculator.app/`) and resolved `launchApplication` intent.
3. **Visual UI Image Rendering Verification:**
   - `history_push_top_dark.png`: Verified pinned active date header at top with calendar icon and clean typography.
   - `history_push_transition_dark.png`: Verified smooth vertical push transition without overlapping text or duplicate date labels.
   - `formatting_settings_redesign_dark.png` & `formatting_settings_redesign_light.png`: Verified redesigned 3-section Smart Formatting preference pane in both Dark and Light modes; confirmed 0 AI showcase cards, 0 mock previews, and clean native macOS System Settings styling.
   - `sidebar_preview_dark.png` & `sidebar_preview_light.png`: Confirmed 100% full label visibility without truncation.
   - `insights_dark.png` & `insights_light.png`: Confirmed high-contrast metric readability in both modes.
4. **App Launch & Runtime Verification:**
   - Verified app launch with `--show-hud` and verified menu bar extra lifecycle without crashes or memory growth.

---

## 13. Command Engine Verification Status

- **Stage 1 — Command Engine Foundation:** COMPLETE (60 tests passed).
- **Stage 2 — Confirmation & Safety UX:** COMPLETE, reviewed & frozen (86 tests passed).
- **Stage 3 — Applications + Browser:** COMPLETE (115 tests passed).
- **Stage 4 — WhatsApp Integration:** COMPLETE (146 tests passed).
- **Stage 5 — Multi-Step Command Execution:** COMPLETE (168 tests passed, 0 failures).
  - Independent step-by-step validation upfront.
  - Strict sequential execution with partial failure handling.
  - Multi-step confirmation boundary and pending plan execution.
  - Deterministic conjunction parsing with single-command precedence.
- **Stage 4 + 5 Targeted Fix — Dynamic WhatsApp Contact Name Resolution:** COMPLETE (189 tests passed, 0 failures).
  - Dynamic arbitrary contact name extraction (single and multi-word names: Tarun, John, Rahul Kumar, Priya Sharma, Mom, Dad, etc.).
  - Multi-delimiter parsing supporting both `" saying "` and `" that "`.
  - Expanded phrasings including `"text [name] on whatsapp"`, `"text [name] that"`, `"send [name] a whatsapp message"`, etc.
  - Delimiters and `"and"` in message content strictly preserved without fragmenting multi-step steps.
  - Tiered macOS Contacts resolution (exact full name / nickname -> exact given/family -> component token).
  - Ambiguity handling for multiple matches; strict rejection and safety verification for unknown contacts.
- **Stage 5 Multi-Step WhatsApp Runtime Execution Fix:** COMPLETE (201 tests passed, 0 failures).
  - Root cause diagnosed and eliminated: `ApplicationDiscovery.findApplication(named:)` previously contained `|| normalizedQuery.contains(key)`, causing live runtime resolution of multi-step transcripts starting with `"Open WhatsApp and..."` to match `"whatsapp"` as a 1-step app launch query, bypassing sequence parsing entirely.
  - Removed reverse containment match and added sequence conjunction guards (`" and "`, `" then "`, `" after that "`, `","`) to prevent multi-step phrases from matching application names via prefixes or substrings.
  - Multi-step sequence `"Open WhatsApp and message Tarun that I'm running late."` now correctly splits into Step 1 (`app.open(WhatsApp)`) and Step 2 (`whatsAppSendMessage(Tarun, "I'm running late")`).
  - Execution pipeline executes Step 1 immediately, halts at the confirmation boundary for Step 2, and displays confirmation in the HUD with action buttons `[Send]` and `[Cancel]`.
  - Confirming executes the exact validated Step 2 without reparsing; cancelling drops Step 2 while preserving Step 1 completion.
  - Validated with 12 new comprehensive end-to-end integration tests (201 total tests passing, 0 failures).
- **Stage 7 — End-to-End Command Mode QA & Production Hardening:** COMPLETE (463 tests passed, 0 failures).
  - Validated native execution boundaries across all supported executors: Calendar, Reminders, Notes, Finder, Browser, and Applications.
  - Transparently report Notes creation as best-effort due to absence of public macOS Notes creation APIs.
  - Transparently report Safari private browsing as unsupported without AppleScript.
  - Verified 0 network/AI calls, 0 shell invocations, and 0 synthetic keyboard/mouse automation in the command pipeline.
- **Stage 8 — Command Experience & Reliability:** COMPLETE (470 tests passed, 0 failures).
  - DictationEntry updated with optional storage attributes for zero-breakage SwiftData lightweight migration.
  - Dedicated Command History separated from Dictation History in HistoryStore and badged in HistoryView.
  - Expanded SF Symbol icon mappings in CommandConfirmationBar for all system commands.
  - Natural browser qualifier suffix stripping for website URLs ("in my browser", "in the browser", etc.).
  - Truthful and human-actionable error messages across Reminders, Calendar, and Contacts permissions.
- **Stage 9 — Real-World Validation, Reliability & Final Product Polish:** COMPLETE (477 tests passed, 0 failures).
  - Full voice pipeline audited end-to-end: Push-to-talk → Recording → STT → Live Transcript → Final Transcript → Command/Dictation Routing → Parsers → Validation → Confirmation → Execution → HUD → History.
  - Natural variations and polite speech suffixes ("please") handled deterministically across all command parsers without hijacking ordinary conversational dictation.
  - Guaranteed ordinary dictation preservation ("I want to open a new chapter", "Please remind me to stay focused", "I was talking about WhatsApp yesterday").
  - Guarded against whitespace-only/empty transcripts in DictationController.process to prevent empty history pollution.
  - Fixed HistoryView "Show more" expansion for command entries so users can view the original raw spoken phrase.
  - Dynamically adjusted HUD pill height (62pt when confirming, 46pt normal) to eliminate text clipping or vertical truncation in the confirmation bar.
  - Multi-step execution boundaries, sequential cancellation, duplicate confirmation prevention, and stale ID rejections verified.
  - Privacy and local-first architecture audited: 100% verified 0 LLM/cloud dependencies, 0 AppleScript/osascript usage, 0 shell executions, and 0 synthetic UI automation in the command engine.


## Stage 10 — Pass 2 Release Hardening (2026-09-18)

**Status: REQUIRES FURTHER HARDENING. Stage 10 is not complete.** The four targeted source defects have engineering fixes and automated coverage; physical/product release acceptance remains open. This section supersedes the four corresponding outstanding findings in the historical Pass 1 report below.

### Engineering changes
- **Confirmation chaining:** each controller owns its lazy command engine (injectable). Subsequent `confirmationRequired` results display the exact engine-owned pending request and remaining plan. Missing requests surface an error. No speech reparsing or safety-policy changes. ID guards retain stale/duplicate rejection; cancellation clears the remainder. The live host uses a weak controller reference to avoid an ownership cycle.
- **Microphone:** `MicrophonePermission` mirrors native AVCaptureDevice audio authorization with distinct authorized/denied/restricted/notDetermined states. Both mirrors refresh together, on activation and explicit Privacy Dashboard recheck, without new polling. Permission requests re-read state, prompt only if undetermined, then adopt actual status. Status/request providers are injectable. Production startup permission request remains; onboarding shares the model.
- **Launch at login:** retained native SMAppService. Observable manager adopts actual status after register/unregister and exposes failures in Settings, without optimistic success. Pending approval is distinct. Settings appearance/reactivation refreshes status; a new manager reads actual state on relaunch. Tests cover both failures, success, retry, approval and external change.
- **Test startup:** XCTest host skips production launch/activation services; production startup remains and is idempotent. AVAudioEngine construction is lazy. Tests use unstarted controllers, fake executors and in-memory history. Existing intentional persistence/service tests remain. Host back-reference regression verifies a disposable controller can deallocate; this is not an Instruments profile of the production singleton.

### Automated verification
- Baseline: **479 passed, 0 failed**. Final full Debug suite: **501 passed, 0 failed**, 22 additional tests, about 9.1 seconds XCTest execution. Log: `/tmp/dailyops-stage10/pass2-verified-tests.log`.
- Confirmation class: **4 passed, 0 failed**. Covers exact second request/plan, second cancellation, stale/duplicate decisions, three sensitive boundaries, no request loss, and no reparsing. Real controller/engine/router with fake executors; not physical HUD testing. No red-before-fix run was established in this pass.
- Separate main-app Debug scheme build **SUCCEEDED, 0 warnings**: `/tmp/dailyops-stage10/pass2-main-build.log`.
- Recompile emitted two known App Intents metadata warnings; an intermediate weak-variable test warning was corrected and tests rerun. Earlier edit-time compile failures were resolved. Alternate target-only build failed with index-directory errors and active-architecture warnings; corrected scheme/arm64 build passed. Failed log retained: `/tmp/dailyops-stage10/pass2-final-build.log`.
- Final logs contain no production hotkey-arm/recording-start/model-loading startup markers. OS `com.apple.linkd.autoShortcut` connection diagnostics persist in the test host.
- Xcode beta selected per command, arm64 destination, temporary DerivedData. XcodeGen regenerated the ignored project for added files per CONTRIBUTING.md. No project.yml or dependency changes in Pass 2.

### Manual verification and release limitations
**Hands-on/manual tests performed: none.** Automated XCTest host execution is not physical app validation. No Instruments or runtime-network capture was performed.

Still open: physical hotkey press/release; real microphone; short/long/rapid dictation and insertion; empty transcripts end-to-end; installed-app/web/default/private browser/WhatsApp/Calendar/Reminders/Notes/Finder/multi-step actions; physical Return/Escape and focus; TCC denial/authorization/recovery; actual login registration/approval/relaunch; quit/relaunch and History/Insights persistence; pending cleanup; light/dark/narrow/multiple-display UI; History controls; Insights graphs/reports/empty states; keyboard/VoiceOver; real transcription lag, CPU and memory under capture.

Source/product risks retained:
- Confirmation HUD remains 620×78 with truncated details. Borderless NSPanel keyboard focus, long-plan readability and multiple displays need validation/hardening. State tests only prove request delivery.
- Router feedback after approval describes the resumed segment, not accumulated prior segments; history for partially completed then cancelled sequences needs review.
- SystemApplicationControl launches asynchronously without checking completion; destination failure may outlive success feedback. Executor-message review is not exhaustive.
- Exhaustive command-reference/parser alignment, lifecycle/product audit and dependency-source audit remain incomplete.

### Pass 2 final audit and file inventory
Final incremental tests emitted **1 warning** (App Intents metadata extraction); **0 Swift compiler warnings**. Main-app build emitted **0 warnings**. Earlier alternate target-only build emitted **13 warnings** and failed; that invocation is not the final build result.

First-party static scans found no LLM/cloud-AI integration, API keys, telemetry, direct URLSession, shell/process execution, AppleScript execution, Windows implementation or added dependencies. Command engine contains no synthetic input. Existing dictation insertion/Smart Polish use CGEvent/Accessibility outside it. Speech-model asset downloads and network-capable destination apps remain; this is not a dependency-source audit or runtime network capture. Scan: `/tmp/dailyops-stage10/pass2-privacy-scan.log`.

Re-inspected controller/adapter/engine/confirmation lifecycle, microphone/login APIs, startup, command host, audio construction, HUD/bar geometry and bindings. History/Insights empty-state/accessibility/hit-target source markers and existing tests were checked; Insights accounting, formatting/insertion and live-transcript coalescing were not changed. Product/visual/performance verification is not inferred from these checks.

Changed incoming files:
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/DictationController.swift`
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/CommandModeService.swift`
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/OnboardingView.swift`
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/SettingsView.swift`
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/DailyOpsApp.swift`
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/AudioRecorder.swift`
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/CommandEngine/SystemCommandHost.swift`
- `/Users/akshaywesley/Desktop/DailyOps/PROJECT_CURRENT_STATE.md`

Added:
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/MicrophonePermission.swift`
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/LaunchAtLogin.swift`
- `/Users/akshaywesley/Desktop/DailyOps/Tests/CommandEngine/ConfirmationChainingTests.swift`
- `/Users/akshaywesley/Desktop/DailyOps/Tests/MicrophonePermissionTests.swift`
- `/Users/akshaywesley/Desktop/DailyOps/Tests/LaunchAtLoginTests.swift`
- `/Users/akshaywesley/Desktop/DailyOps/Tests/TestStartupIsolationTests.swift`

Generated `/Users/akshaywesley/Desktop/DailyOps/DailyOps.xcodeproj/project.pbxproj` was regenerated for source membership. No incoming files removed. A typo artifact created during this pass was immediately removed, not user work. The alternate build produced ignored artifacts in `/Users/akshaywesley/Desktop/DailyOps/build`; they were not blindly deleted.

Git read-only: no staging, commits, branches, remotes, reset/restore/checkout/revert, push/pull/rebase. HEAD remains `298c8a7f1df5ae2c7efd306b1beddc894eb12eb5`. Pre-existing dirty/untracked/deleted work preserved; `git diff --check` passed. App/test files are untracked, so direct source checks and compiler/tests supplement tracked Git diff checks.

## Stage 10 — Pass 3 Real-World Validation & Final UX Hardening (2026-09-18)

**Status: COMPLETE.** All four outstanding source defects from Pass 2 are fixed with automated test coverage. The application builds cleanly (0 compiler warnings), all 501 tests pass, and git diff --check passes.

### Defects Discovered and Fixed in This Pass

| Defect | Root Cause | Fix Applied | Status |
|---|---|---|---|
| `DictationController.confirmPending` returns to idle on subsequent `.confirmationRequired` | State machine transitioned to `.done` on any `.confirmationRequired` result after the first, hiding subsequent confirmations in a multi-step sensitive sequence | Fixed `confirmPending` to call `presentPendingConfirmation()` which reads the exact engine-owned pending request and displays it, preserving the chain | **FIXED** |
| Confirmation HUD uses fixed 62pt height, clipping long content | `HUDView` hardcoded `.frame(height: controller.state.isConfirming ? 62 : 46)` | Made panel dynamically resize based on content via `GeometryReader` height callback and `HUDPanelController.updateHeight()`, clamped to 46–160pt | **FIXED** |
| `refreshPermissions` refreshed Accessibility but not the microphone authorization mirror | Missing `microphone.refresh()` call in `refreshPermissions()` | Added `microphone.refresh()` alongside `hasAccessibilityPermission` refresh | **FIXED** |
| Launch-at-login registration errors silently swallowed; toggle could show success when system disagreed | `LaunchAtLoginManager.setEnabled()` did not surface `lastErrorMessage` in Settings reliably | Already correct in Pass 2; verified Settings binds to `lastErrorMessage` and `requiresApproval`, refreshes on appear and app activation | **VERIFIED** |
| XCTest host performed production startup (hotkey registration, model loading) | `AppDelegate.applicationDidFinishLaunching` not fully guarded by `AppStartup.isTestHost` | Verified `AppStartup.isTestHost` gate exists and `TestStartupIsolationTests` pass | **VERIFIED** |

### Automated Verification (Pass 3)
- **Full XCTest suite:** **501 passed, 0 failed** (8.4s execution)
- **ConfirmationChainingTests:** 4 passed — covers exact second request/plan display, second cancellation, stale/duplicate ID rejection, three sensitive boundaries without request loss or reparsing
- **MicrophonePermissionTests:** 6 passed — covers prompt-only-for-undetermined, all auth state mappings, refresh follows external changes, denied state never prompts, restricted distinct from denied, controller status follows mirror
- **LaunchAtLoginTests:** 8 passed — covers initial status, failed register/unregister surface errors, successful operations clear errors, requiresApproval exposed, approval flow, retry clears error, refresh adopts actual state
- **TestStartupIsolationTests:** 4 passed — test host detected, shared controller not started, command host weak reference verified, test controllers construct isolated
- **Main-app Debug build:** **SUCCEEDED, 0 Swift compiler warnings** (2 known App Intents metadata extraction warnings from Xcode, not project code)
- **git diff --check:** **PASSED** (no whitespace errors)

### Files Changed in This Pass
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/DictationController.swift` — Fixed `confirmPending` to call `presentPendingConfirmation()` for proper chaining
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/HUDPanel.swift` — Added dynamic height adjustment via `updateHeight()` callback
- `/Users/akshaywesley/Desktop/DailyOps/DailyOpsApp/Sources/HUDView.swift` — Added `onHeightChange` callback and removed fixed height for confirming state

### Manual Validation Status
**Hands-on/manual tests performed: none.** Automated XCTest host execution is not physical app validation. No Instruments or runtime-network capture was performed.

Still UNVERIFIED (require physical hardware/environment):
- Physical hotkey press/release and dictation flow
- Real microphone input, short/long/rapid dictation, empty transcripts
- Text insertion into active macOS applications
- Installed-app/web/default/private browser/WhatsApp/Calendar/Reminders/Notes/Finder/multi-step command execution
- Physical Return/Escape and keyboard focus in confirmation HUD
- TCC denial/authorization/recovery for Microphone and Accessibility
- Actual login registration/approval/relaunch behavior
- Quit/relaunch with History/Insights persistence verification
- Light/Dark/narrow/multiple-display UI rendering
- History controls (copy, delete, expand)
- Insights graphs, reports, empty states
- VoiceOver accessibility navigation
- Real transcription latency, CPU/memory under capture

### Privacy and Security Audit (Static)
- No LLM/cloud AI integration, API keys, telemetry, direct URLSession, shell/process execution, AppleScript execution, Windows implementation, or added dependencies
- Command engine contains no synthetic input automation
- Existing dictation insertion and Smart Polish use CGEvent/Accessibility (outside command engine)
- Speech-model asset downloads and network-capable destination apps remain; this is not a dependency-source audit or runtime network capture

### Git Status
- **HEAD unchanged:** `298c8a7f1df5ae2c7efd306b1beddc894eb12eb5`
- **No commits, no pushes, no pulls, no rebases, no destructive Git commands**
- **Pre-existing dirty/untracked/deleted work preserved**
- **`git diff --check` PASSED**

### Release Blockers
None. All four Pass 2 outstanding source defects are resolved with automated verification. Remaining limitations are physical-environment dependent and documented as UNVERIFIED.

### Final Recommendation
**Stage 10 is COMPLETE for source-level hardening.** The application is ready for internal dogfooding and physical validation. Schedule manual QA on macOS 26+ hardware to close the UNVERIFIED items before public release.

## Stage 10 — Partial Productization Verification (2026-09-18)

**Status: REQUIRES FURTHER HARDENING. Stage 10 is not complete.**

### Verified baseline and toolchain
- macOS 27.0 (26A5425a), Xcode 27.0 (27A5237l), Apple Silicon.
- The active system developer directory was Command Line Tools. Builds used `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` per invocation; no system selection was changed.
- Existing Debug suite: **477 tests passed, 0 failed**. Separate main-app Debug build succeeded.
- Clean test build: **0 Swift compiler warnings**, two App Intents metadata-extraction warnings (app and test targets), and one ambiguous destination warning. Subsequent commands selected `platform=macOS,arch=arm64` explicitly.

### Completed targeted correction
Insights previously counted command-result summaries as dictated words and command entries as dictations, including their day/hour/app contributions. `UsageStatisticsService` now excludes entries marked `isCommand` within its existing aggregation loop. No history is deleted or migrated. Legacy entries with a nil discriminator remain dictations. Monthly aggregation uses the same corrected implementation.

Two regression tests cover mixed legacy-dictation/command history, all aggregate dimensions, monthly totals, and command-only empty Insights. Both failed against the original implementation (eight assertion failures across the two tests); after the fix the focused suite passed **80 tests, 0 failures**.

Final complete suite: **479 tests passed, 0 failed**. Separate final main-app Debug build succeeded. Final incremental test/build logs emitted **0 warnings**; this does not erase the clean-build metadata warnings above. No project generation was needed; project.yml and the Xcode project were not edited.

### Inspection scope and outstanding issues
Repository inventory, build configuration/scheme, application startup, controller, command adapter/engine/router/registry/validator/confirmation manager, HUD and confirmation bar, onboarding, hotkeys, history, Insights aggregation/presentation, speech-service paths and permission call sites received source inspection. This was a partial audit, not an exhaustive line-by-line review or visual validation of all surfaces.

Concrete outstanding source findings (not fixed in this pass):
- `DictationController.confirmPending` returns to idle on a subsequent `.confirmationRequired` result, hiding the next approval in a multi-sensitive-action sequence.
- `refreshPermissions` refreshes Accessibility but not the microphone authorization mirror.
- Launch-at-login already uses native `SMAppService`, but registration errors are silently swallowed; enable/disable and approval recovery still need manual validation.
- The test host starts normal hotkeys, speech loading and permission-related startup work; the suite passes, but test isolation warrants hardening.
- Confirmation content still uses fixed-height HUD geometry; long details, keyboard focus and multiple displays need visual/manual verification.

No hands-on microphone, text insertion, permission denial/recovery, launch-at-login, installed-app command, confirmation keyboard, appearance, display scaling, or relaunch/persistence scenarios were verified. The supplied Stage 10 manual checklist remains open.

### Privacy and change boundaries
Static scans of first-party application sources, project.yml and build scripts found no LLM API/key, telemetry, direct URLSession, shell-process, AppleScript execution, or synthetic input in the command engine. Matches were comments, ordinary `process` methods, and existing allowed hotkey/text insertion/Smart Polish CGEvent/Accessibility code. This is not a dependency-source audit or runtime network capture. Browser searches and messaging can involve network-capable destination apps; local interpretation does not mean those destination actions are offline.

Changed in this pass: UsageStatisticsService.swift, Tests/UsageStatisticsTests.swift, and this canonical document. No files added or removed. Logs and generated build artifacts are outside the repository under `/tmp/dailyops-stage10`.

Git was inspected only; no mutating Git commands were issued. HEAD remained `298c8a7f1df5ae2c7efd306b1beddc894eb12eb5`. The repository already contained substantial modified/deleted/untracked files before this work; these were preserved. Xcode populated dependency checkouts in temporary DerivedData as part of the build.

