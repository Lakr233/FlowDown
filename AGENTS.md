# FlowDown Agent Guide

This file provides guidance to AI coding agents working inside this repository.

## Overview

FlowDown is a Swift-based AI/LLM client for iOS and macOS (Catalyst) with a privacy-first mindset. The workspace hosts the main app plus several Swift Package Manager frameworks (e.g. `ChatClientKit`, `Storage`, `Logger`) that power storage, editing, model integrations, and on-device MLX inference. Persistent configuration lives in the `ConfigurableKit` package.

- All code text (UI strings, comments, logs) must remain in English.

## Environment & Tooling

- Prefer opening `FlowDown.xcworkspace` so the app and frameworks resolve together under shared schemes.
- `ChatClientKit` intentionally relies on the `FlowDown.xcworkspace` package override for `mlx-swift-lm`; keep `Frameworks/ChatClientKit/Package.swift` on `branch: "main"` for that dependency and validate integration changes through workspace builds driven by the top-level `Makefile`.
- Use Xcode 26.x (Swift 6.0 toolchain) or newer to satisfy package manifests and the Swift `Testing` library.
- Build on macOS 26 or later to ensure compatibility with the required toolchain.
- Install `xcbeautify` (`brew install xcbeautify`) so the shared `make` workflows can produce readable logs.
- Lean on automation in `Resources/DevKit/scripts/` (localization, archiving, licensing) instead of ad-hoc scripts.
- Always use the top-level `Makefile` for build, test, package resolution, archive, and verification flows.
- Do not run `xcodebuild` directly in the shell. If a workflow is missing, add a `Makefile` target first.

## Platform Requirements & Dependencies

- Target platforms reflect framework minimums: iOS 17.0+, macCatalyst 17.0+ (macOS 14+ for Catalyst helpers).
- Toolchain: Swift 6.0 (`swift-tools-version: 6.0`) and the Xcode 26 SDK line are required. MLX currently resolves to `mlx-swift` 0.21.x and `mlx-swift-examples` on `main`.
- Core SwiftPM dependencies include MLX/MLX examples, ConfigurableKit, SnapKit, SwifterSwift, MarkdownView, WCDB prebuilt binaries, ZIPFoundation, ScrubberKit, AlertController, GlyphixTextFx, ColorfulX, UIEffectKit, DpkgVersion, swift-transformers, and additional UI/tooling libraries listed in `FlowDown.xcodeproj`.
- `Storage` wraps WCDB with Markdown parsing and ZIP export; `ChatClientKit` layers MLX, EventSource, and Logger to deliver on-device and streaming chat.
- MLX GPU support is automatically detected and disabled in simulator/x86_64 builds (see `FlowDown/main.swift`).

## Project Structure

- `FlowDown.xcworkspace`: Entry point with app and frameworks.
- `FlowDown/`: Application sources divided into `Application/` (entry surfaces), `Backend/` (conversations, models, storage, security), `Interface/` (UIKit), `PlatformSupport/` (macOS/Catalyst glue), and `BundledResources/` (curated assets shipped with the app).
- `FlowDown/DerivedSources/`: Generated during builds (`BuildInfo.swift`, `CloudKitConfig.swift`). Treat as generated—schemes will overwrite changes.
- `Frameworks/`: Shared Swift packages (`ChatClientKit`, `Storage`, `RichEditor`, `RunestoneEditor`, `Logger`). Each package owns its manifest and dependency graph.
- `FlowDownUnitTests/`: App-level tests using Swift's `Testing` package (`@Test` entry points).
- `Resources/`: Shared assets, localization collateral, privacy documents, and DevKit utilities.
- `Resources/DevKit/scripts/`: Automation helpers (archiving, translation, licence scanning). Prefer extending these over new stand-alone scripts.
- `Playgrounds/`: Exploratory prototypes; do not assume production readiness.

## Build & Run Commands

- Open the workspace: `open FlowDown.xcworkspace`.
- Build commands:
  - `make build` for the iOS and Mac Catalyst app
  - `make build-ios` for the iOS app
  - `make build-catalyst` for the Mac Catalyst app
  - `make build-extension` for the translation provider extension
- Test commands:
  - `make test` for the default test flow
  - `make test-unit` for app tests on the first available iOS simulator
  - `make test-chat-client-kit` for ChatClientKit package tests on macOS; use `CHAT_CLIENT_KIT_TEST_ARGUMENTS` to focus a suite when needed
  - `make test-online-e2e` for the online E2E suite
- Package and license commands:
  - `make package-resolve` to resolve SwiftPM packages
  - `make package-verify` to confirm `Package.resolved` still carries the pins Xcode Cloud requires
  - `make scan-license` to refresh `OpenSourceLicenses.md`
- Localization commands:
  - `make localization-check` to check for missing translations
  - `make localization-stale-check` to prune stale keys and verify completeness
- Archive commands:
  - `make archive` for both platforms
  - `make archive-ios` for the iOS archive
  - `make archive-macos` for the macOS archive
- Cleanup commands:
  - `make clean-build` to remove repo-local build artifacts
  - `make clean` to remove repo-local build artifacts and derived data
- The shared FlowDown scheme runs `git submodule update` before builds and tests; stage or commit intended gitlink changes first so the selected submodule revisions are not restored from the index.
- Build wrappers must distinguish structured compiler/test failures from runtime log messages containing `error:` so negative-path tests can exercise and log expected failures without turning a successful test session red.
- Xcode Cloud invokes `xcodebuild` outside the Makefile; keep package plug-in validation configuration in `ci_scripts/ci_post_clone.sh` so cloud archives receive it.
- Xcode 27's resolver prunes pins no built target links (currently `swift-argument-parser`, pulled in by `mlx-swift`), but Xcode Cloud's older toolchain rejects a `Package.resolved` that omits them. Any resolve or build drops the pin again, so `Resources/DevKit/required-package-pins.json` declares it and `required_package_pins.py fix` re-adds it after every resolve. Never hand-delete those pins to make a local diff smaller; run `make package-verify` before committing `Package.resolved`.
- Archive script automatically commits changes and bumps version before building; ensure the working tree is clean beforehand.
- Use `make help` to discover the current command surface.
- Localization validation helpers:
  - `make localization-stale-check`
  - `make localization-check`
  - `python3 Resources/DevKit/scripts/update_missing_i18n.py FlowDown/Resources/Localizable.xcstrings` to scaffold missing locales; extend `NEW_STRINGS` in that script when adding new keys.

## Shell Script Style

### Core Principles

- **Simplicity**: Keep scripts minimal and focused
- **No unnecessary complexity**: Avoid features that aren't needed
- **Visual clarity**: Use line breaks for readability
- **Failure handling**: Use `set -euo pipefail`
- **Use shebang for scripts**: Use `#!/bin/zsh`

### Output Guidelines

- Use `[+]` for successful operations
- Use `[-]` for failed operations (when needed)
- Keep echo messages lowercase
- Simple status messages: "building...", "completed successfully"

### Code Style

- Minimal comments - focus on self-evident code
- No unnecessary color output or visual fluff
- Line breaks for long command chains
- Assume required tools are available (e.g., xcbeautify)
- Don't add if checks when pipefail handles failures

## Development Guidelines

### Swift Style

- 4-space indentation with opening braces on the same line
- Single spaces around operators and after commas
- PascalCase types; camelCase properties, methods, and file names
- Organize extensions into targeted files (`Type+Feature.swift`) and keep each file focused on one responsibility
- Lean on modern Swift patterns: `@Observable`, structured concurrency (`async`/`await`), result builders, and protocol-oriented design

### Architecture & Key Services

- Respect the established managers: `ModelManager`, `ModelToolsManager`, `ConversationManager`, `MCPService`, and `UpdateManager`. Consult them before adding new singletons.
- Compose features via dependency injection and protocols instead of inheritance.
- Keep Catalyst-specific behaviour under `PlatformSupport/` to avoid leaking platform checks throughout the codebase.
- Security hardening lives in `FlowDown/Backend/Security/`: release builds validate app signatures, strip debuggers, and verify sandbox enforcement (see `main.swift`).
- Backend services are organized by domain: `ChatTemplate`, `Conversation`, `Model`, `ModelTools`, `MCPService`, `Storage`, `Security`, `UpdateManager`.
- `main.swift` wires storage (`Storage.db()`), CloudKit sync, logging, and shared singletons (`ModelManager`, `ModelToolsManager`, `ConversationManager`, `MCPService`, `UpdateManager`, `ChatSelection`). Keep this order intact to avoid race conditions.
- `ConfigurableKit` powers persisted user settings—add keys through dedicated `Value+*.swift` helpers and publish updates via its typed publishers.
- Continuous input (drags, live resizes) must coalesce onto a `CADisplayLink` before running an animated layout pass. Animating on every event outruns the run loop's commit, so nothing is presented, no animation completes to be reclaimed, and each pass walks a longer list of live animations until the window appears frozen.
- For local MLX tool calling, derive the parser from the checkpoint's chat-template protocol and carry that override through directory-based model loading; the architecture type alone does not identify function-calling fine-tunes such as FunctionGemma.
- Preserve tool-event source order and always finalize EOS-delimited parsers. If a one-tool Mistral request produces only a bare JSON argument object at EOS, infer the function name only from that single selected schema and never expose the protocol payload as assistant text.
- Treat Foundation Models streaming partials as cumulative text followed by at most one captured tool invocation: emit only text deltas, then make the tool event terminal so the caller can execute it and submit the result on the next turn.
- Runtime availability checks cannot make newer SDK members compile with Xcode 26. Keep Foundation Models request construction on APIs declared by the minimum supported SDK, and express newer tool-choice semantics through existing tool selection and instructions unless the build itself is compiler-gated.
- When a model object exposes `package(set)` state through public update methods, do not carry a writable key path across the package boundary; model the closed set of target fields explicitly and invoke the owner's update API inside each branch.
- For local reasoning models, use the resolved model `reasoningConfig` and seed stream routing from the prepared prompt. Chat templates may prefill the opening reasoning delimiter, so generated output can begin inside reasoning and emit only the closing delimiter; parsers must also preserve partial delimiters across chunks.
- Treat evaluation tool parameters as a wire-schema boundary: normalize shorthand parameter types into a root `type: object` JSON Schema before inference, preserve already-complete schemas, and test the encoded request shape against provider validation. Verify no-argument calls explicitly by tool name instead of leaving their verifier list empty.

## Testing Expectations

- Add or update unit/UI tests alongside behavioural changes. `FlowDownUnitTests` leverages the Swift `Testing` library—author tests as `@Test func featureScenario_expectation()`.
- Keep `@Test` enablement predicates free of test events and side effects; optional fixture probes should return `false` when unavailable and only record failures from inside an enabled test.
- Keep local test servers independent of reverse DNS; bind to the requested numeric host and publish the bound address directly.
- When a model workflow changes its structured-output contract, migrate its replay request/response fixtures in the same change and run `make test-online-e2e`.
- Route replay fixtures by their most specific semantic discriminator, such as a required tool name, before applying generic stream or transport fallbacks.
- Run app-level tests through `make test` or `make test-unit`.
- Use `make test-online-e2e` when a change needs the online E2E suite.
- Document manual verification steps whenever UI or integration flows lack automation.

## Security & Privacy

- Never hardcode secrets; rely on user-supplied keys and platform keychains.
- Validate new managers or services against the sanctioned singleton list above.
- Use `assert`/`precondition` to capture invariants during development.
- Audit persistence changes for privacy impacts before shipping.
- Preserve existing safeguards in `main.swift`: release builds disable stdout/stderr, strip debuggers, enforce signature validation, and ensure Catalyst sandboxing.
- Keep CloudKit identifiers, entitlements, and derived `CloudKitConfig.swift` generation in sync with deployment environments.

## Documentation & Knowledge Sharing

- Capture key findings from external research in PR descriptions so future contributors can trace decisions.
- Reference official docs, WWDC sessions, or sample projects when introducing new APIs.
- Keep architectural rationale and trade-offs close to the code (doc comments or dedicated markdown) when complexity grows.
- Call out changes to generated assets or DevKit scripts (`FlowDown/DerivedSources`, `Resources/DevKit/scripts/`) in PR summaries so reviewers can trace automation impacts.

## Collaboration Workflow

- Craft concise, capitalized commit subjects (e.g., `Adjust Compiler Settings`) and use bodies to explain decisions or link issues (`#123`).
- Group related work per commit and avoid bundling unrelated refactors.
- Pull requests must include a summary, testing checklist, and before/after visuals for UI changes. Mention localization or asset updates when relevant.
- Tag reviewers responsible for the affected modules and outline any follow-up tasks or risks.

## Code Review Guidelines

- Keep reviews pragmatic: prioritize reproducible, high-impact defects with clear user or data risk.
- Do not report intentional fail-fast patterns as bugs by default (`force unwrap`, `as!`, `try!`, `unowned`) when they protect explicit invariants.
- If an invariant can be violated, prefer explicit fail-fast checks (`precondition`/`assert`) over silent fallbacks that hide corruption.
- Avoid recommending fixes for extremely low-probability race conditions unless impact is severe or reproduction is clear.
- Prefer root-cause fixes over broad defensive rewrites that mostly reduce crash visibility without improving correctness.
- Write findings as actionable items: include trigger condition, concrete impact, and minimal viable fix.

### CI Review Check

- For GitHub Actions workflows that build, test, or archive through `make` or project scripts, ensure the Metal toolchain is downloaded before the first build step.
- Keep Xcode selection aligned across build, test, archive, and notarization workflows so releases do not run on an obsolete toolchain after CI advances.
- Treat Catalyst entitlement changes and Xcode upgrades as signing-profile migrations; keep the notarization profile in sync and validate the final Developer ID signature before publishing the next release.

## Localization Guidelines

- `AlertViewController` and `ConfigurableKit` APIs expect `String.LocalizationValue`; pass localization values directly for consistency
- Other UI entry points should continue using `String(localized: ...)` for user-facing strings
- Source all user-visible strings from localization files instead of hardcoded literals

### Dynamic values (avoid missed translations)

When a localized string includes runtime values (counts, sizes, etc.), do NOT build the key as a `String` via interpolation.

- Bad (produces a runtime `String` key like "3 chances" and will NOT match entries like "%lld chances"):
  - `String(localized: "\(value) chances")`
- Good (ensures a `String.LocalizationValue` is produced, so it matches the formatted key in `.xcstrings`):
  - `let key: String.LocalizationValue = "\(value) chances"`
  - `String(localized: key)`

Prefer `String.LocalizationValue`/`LocalizedStringResource` formatting over `String(format:)` in app code. Use `String(format:)` only when needed for compatibility.

- Main app localization files:
  - `FlowDown/Resources/Localizable.xcstrings`: Main app UI strings
  - `FlowDown/Resources/InfoPlist.xcstrings`: Info.plist localization strings
- Translation provider localization files:
  - `FlowDownTranslationProvider/Localizable.xcstrings`: Translation provider UI strings
  - `FlowDownTranslationProvider/InfoPlist.xcstrings`: Translation provider Info.plist localization strings
- FlowDownWidgets localization files:
  - `FlowDownWidgets/Localizable.xcstrings`: Widgets UI strings
  - `FlowDownWidgets/InfoPlist.xcstrings`: Widgets Info.plist localization strings
- We ship multiple locales (en base plus de, es, fr, ja, ko, zh-Hans); keep all locales populated when adding or updating strings—do not leave only English/Chinese
- **IMPORTANT**: When adding new strings, you MUST provide translations for ALL supported languages (de, es, fr, ja, ko, zh-Hans) in `NEW_STRINGS`. Never add strings with only partial translations.
- **IMPORTANT**: When adding new strings, you MUST provide translations for ALL supported languages (de, es, fr, ja, ko, zh-Hans) in `NEW_STRINGS`. Never add strings with only partial translations.
- Use the provided scripts to manage translations:
  - `python3 Resources/DevKit/scripts/update_missing_i18n.py FlowDown/Resources/Localizable.xcstrings` to scaffold new keys (extend `NEW_STRINGS` dict in the script as required)
  - `python3 Resources/DevKit/scripts/translate_missing.py FlowDown/Resources/Localizable.xcstrings` to apply curated zh-Hans translations
  - `python3 Resources/DevKit/scripts/check_untranslated.py FlowDown/Resources/Localizable.xcstrings` to surface untranslated entries (missing or empty) across ALL languages
  - `python3 Resources/DevKit/scripts/check_translations.py FlowDown/Resources/Localizable.xcstrings` to remove stale keys and verify completeness across all locales
- Script usage notes:
  - `update_missing_i18n.py`: Add translations for ALL languages to `NEW_STRINGS` dict before running; the script merges them into xcstrings. Format: `{"Key": {"de": "...", "es": "...", "fr": "...", "ja": "...", "ko": "...", "zh-Hans": "..."}}`
  - `check_untranslated.py`: Reports strings missing translations in ANY supported language (not just zh-Hans)
  - `check_translations.py`: Use this to find strings missing translations in any locale (missing, empty, or non-translated state)
- Localization files such as `Localizable.xcstrings` exceed 10k lines; update the supporting Python scripts to regenerate changes instead of editing the JSON directly.
- Follow existing localization patterns and maintain consistency with the codebase. Avoid manual edits to `.xcstrings`; let scripts manage JSON structure.
