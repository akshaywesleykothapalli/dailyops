# DailyOps feature audit

Scope: current Phase 5D2 implementation. Phase 6 and new external integrations remain outside this audit. No claim of universal correctness follows from a passing suite.

## Corrections

- Plans with unsupported required tools now end as failed rather than completed. Failed runs emit the failure event rather than a completion event, preserving the correct checkpoint disposition.
- Failure summaries include unsupported task counts.
- Deterministic cleanup uses the unified preference-aware formatter instead of an extra unconditional filler/repetition/spelling pass.
- Smart Formatting presents Local Text Cleanup and no longer offers inactive Apple Intelligence/Ollama cleanup engine controls. Stored legacy settings are retained.
- Regression assertions cover unsupported plan status and absence of completion events after failure/rejection. A new regression test verifies disabled speech cleanup and spoken punctuation are respected.

## Coverage and limits

| Feature area | Evidence | Remaining practical check |
| --- | --- | --- |
| Speech transcription | Real bundled JFK audio self-test, nonempty accurate transcript | Each selectable engine/language and user's microphone |
| Text cleanup | Real self-test and regression tests; disabled preferences test | User vocabulary and representative multilingual input |
| Hotkey lifecycle and audio prewarm | XCTest hardware-dependent coverage | Actual Fn capture on the user's input device |
| Cursor insertion and clipboard restoration | Paste pipeline tests | Accessibility grant and live insertion into target apps |
| Commands and browser/application routing | Parser, validator, executor, custom command and multistep tests; real app discovery | Live target-app availability and macOS Automation permissions |
| WhatsApp | Contact resolution, validation, confirmation, execution adapter tests | User-authorized real recipient flow; no messages sent during audit |
| Calendar and Reminders | Native command parser/executor and confirmation tests | OS grants and user-authorized live data operations |
| Workspace roles and planning | Runtime, role and session tests | Starter titles do not imply connected services |
| Approvals | Permission and rejection/confirmation tests | Critical actions remain denied by default |
| Persistence/resume | Store, checkpoint, restoration and resume suites | Unsupported/failed sessions require review |
| History, search/grouping and insights | History/statistics/grouping/view-model suites | Representative user history and visual layout |
| Dictionary/context/repeated speech | Context, transcription coordinator and duplicate speech tests | Real target application context and vocabulary |
| Launch at login | Injected SMAppService tests | Real OS registration requires user setting |
| Branding | Complete asset catalog, XcodeGen configuration, built/installed icon hash match and effective NSWorkspace icon | Finder/Dock visual observation was unavailable in the previous release run |

## Features not complete

- Agent GitHub, CI, Calendar and other external tool integrations are not registered. Native Calendar/Reminders command paths are separate.
- Most starter workflows remain deterministic planning templates; descriptive no-tool tasks do not collect real work data.
- Smart Polish's rewrite, formal, concise and summarize actions currently share deterministic formatting rather than distinct semantic transformations.
- Intel builds and verified public signed/notarized release artifacts are not configured/confirmed.

## Environment blockers

The installed app's onboarding reported Microphone Allowed and Speech Model Ready, but Accessibility was missing. Global hotkeys and insertion at the cursor cannot be certified end-to-end until the user enables DailyOps in System Settings → Privacy & Security → Accessibility. Ad-hoc signing can require reauthorization after a rebuild. Live external-app/data operations were not performed.

## Verification

Real audio self-test passed: JFK fixture transcribed in about 0.55 seconds; local cleanup and application discovery passed. Updated full suite: 660 XCTest + 160 Swift Testing, zero failures. Both execution-reporting regressions and the new preference test passed. Release installation is verified separately in the task report.
