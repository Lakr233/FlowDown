# FlowDown Agent Guide

This file provides guidance to AI coding agents working inside this repository.

## Overview

FlowDown is a Swift-based AI/LLM client for iOS and macOS (Catalyst) with a privacy-first mindset. The workspace hosts the main app plus several Swift Package Manager frameworks (e.g. `ChatClientKit`, `Storage`, `Logger`) that power storage, editing, model integrations, and on-device MLX inference. Persistent configuration lives in the `ConfigurableKit` package.

- All code text (UI strings, comments, logs) must remain in English.

## Environment & Tooling

- Prefer opening `FlowDown.xcworkspace` so the app and frameworks resolve together under shared schemes.
- Use Xcode 26.x (Swift 6.0 toolchain) or newer on macOS 26 or later. Install `xcbeautify` (`brew install xcbeautify`) so `make` produces readable logs.
- Always drive build, test, package resolution, archive, and verification through the top-level `Makefile`. Do not run `xcodebuild` directly; if a workflow is missing, add a `Makefile` target first.
- Lean on automation in `Resources/DevKit/scripts/` (localization, archiving, licensing) instead of ad-hoc scripts.
- `ChatClientKit` intentionally relies on the workspace package override for `mlx-swift-lm`; keep `Frameworks/ChatClientKit/Package.swift` on `branch: "main"` for that dependency and validate integration changes through workspace builds.

## Platform Requirements & Dependencies

- Target platforms reflect framework minimums: iOS 17.0+, macCatalyst 17.0+ (macOS 14+ for Catalyst helpers).
- Toolchain: Swift 6.0 (`swift-tools-version: 6.0`) and the Xcode 26 SDK line. MLX currently resolves to `mlx-swift` 0.21.x and `mlx-swift-examples` on `main`.
- Core SwiftPM dependencies include MLX/MLX examples, ConfigurableKit, SnapKit, SwifterSwift, MarkdownView, WCDB prebuilt binaries, ZIPFoundation, ScrubberKit, AlertController, GlyphixTextFx, ColorfulX, UIEffectKit, DpkgVersion, swift-transformers, and additional UI/tooling libraries listed in `FlowDown.xcodeproj`.
- `Storage` wraps WCDB with Markdown parsing and ZIP export; `ChatClientKit` layers MLX, EventSource, and Logger to deliver on-device and streaming chat.
- MLX GPU support is automatically detected and disabled in simulator/x86_64 builds (see `FlowDown/main.swift`).

## Project Structure

- `FlowDown/`: Application sources divided into `Application/` (entry surfaces), `Backend/` (conversations, models, storage, security), `Interface/` (UIKit), `PlatformSupport/` (macOS/Catalyst glue), `Extension/`, and `BundledResources/` (curated assets shipped with the app).
- `FlowDown/DerivedSources/`: Generated during builds (`BuildInfo.swift`, `CloudKitConfig.swift`). Treat as generated—schemes will overwrite changes.
- `Frameworks/`: Shared Swift packages (`ChatClientKit`, `Storage`, `Logger`, `RunestoneEditor`, `FlowDownModelExchange`) plus the `mlx-swift-lm` submodule. Each package owns its manifest and dependency graph.
- `FlowDownUnitTests/`: App-level tests using Swift's `Testing` package (`@Test` entry points).
- `Resources/`: Shared assets, localization collateral, privacy documents, and DevKit utilities. `Resources/DevKit/scripts/` holds the automation helpers—extend these rather than adding stand-alone scripts.
- `Examples/`: Companion sample projects (e.g. `ModelExchange`); not shipped with the app.

## Build & Run Commands

- Run `make help` for the current command surface. The common targets:
  - Build: `make build`, `build-ios`, `build-catalyst`, `build-extension`
  - Test: `make test`, `test-unit`, `test-chat-client-kit` (set `CHAT_CLIENT_KIT_TEST_ARGUMENTS` to focus a suite), `test-online-e2e`
  - Packages and licenses: `make package-resolve`, `package-verify`, `scan-license`
  - Localization: `make localization-check`, `localization-stale-check`
  - Archive: `make archive`, `archive-ios`, `archive-macos`
  - Cleanup: `make clean-build`, `make clean`
- The shared FlowDown scheme runs `git submodule update` before builds and tests; stage or commit intended gitlink changes first so the selected submodule revisions are not restored from the index.
- Xcode 27's resolver prunes pins no built target links (currently `swift-argument-parser`, pulled in by `mlx-swift`), but Xcode Cloud's older toolchain rejects a `Package.resolved` that omits them. `Resources/DevKit/required-package-pins.json` declares them and `required_package_pins.py fix` re-adds them after every resolve. Never hand-delete those pins to shrink a diff; run `make package-verify` before committing `Package.resolved`.
- Xcode Cloud invokes `xcodebuild` outside the Makefile; keep package plug-in validation configuration in `ci_scripts/ci_post_clone.sh` so cloud archives receive it.
- The archive script requires a clean working tree, then bumps the build number and commits before building.

## Shell Script Style

- `#!/bin/zsh`, `set -euo pipefail`, and no `if` checks for what pipefail already catches.
- Keep scripts minimal: no color output or visual fluff, minimal comments, line breaks for long command chains.
- Lowercase status messages ("building...", "completed successfully"); `[+]` for success and `[-]` for failure.
- Assume required tools are available (e.g. xcbeautify).

## Development Guidelines

### Swift Style

- 4-space indentation with opening braces on the same line; single spaces around operators and after commas.
- PascalCase types; camelCase properties, methods, and file names.
- Organize extensions into targeted files (`Type+Feature.swift`) and keep each file focused on one responsibility.
- Lean on modern Swift patterns: `@Observable`, structured concurrency (`async`/`await`), result builders, and protocol-oriented design.

### Architecture & Key Services

- Respect the established managers: `ModelManager`, `ModelToolsManager`, `ConversationManager`, `MCPService`, and `UpdateManager`. Consult them before adding new singletons.
- Compose features via dependency injection and protocols instead of inheritance.
- Backend services are organized by domain: `ChatTemplate`, `Conversation`, `Model`, `ModelTools`, `MCPService`, `Storage`, `Security`, `UpdateManager`.
- `main.swift` wires storage (`Storage.db()`), CloudKit sync, logging, and shared singletons (`ModelManager`, `ModelToolsManager`, `ConversationManager`, `MCPService`, `UpdateManager`, `ChatSelection`). Keep this order intact to avoid race conditions.
- Keep Catalyst-specific behaviour under `PlatformSupport/` to avoid leaking platform checks throughout the codebase.
- `ConfigurableKit` powers persisted user settings—add keys through dedicated `Value+*.swift` helpers and publish updates via its typed publishers.

### UI

- Continuous input (drags, live resizes) must coalesce onto a `CADisplayLink` before running an animated layout pass. Animating on every event outruns the run loop's commit, so nothing is presented, no animation completes to be reclaimed, and each pass walks a longer list of live animations until the window appears frozen.
- Do not rebuild `UIScrollEdgeEffect` for pre-26 systems. The private `variableBlur` filter honours its mask only on a backdrop layer we own; on a `UIVisualEffectView`'s backdrop UIKit re-asserts the material's own filters and it renders as a uniform blur cut off at the layer edge. The chat header uses a plain `.regular` blur plus a hairline separator below 26, and `UIGlassContainerEffect` at 26+.

### Model Integration

- Derive local MLX tool-call parsers from the checkpoint's chat-template protocol and carry that override through directory-based model loading; the architecture type alone does not identify function-calling fine-tunes such as FunctionGemma.
- Preserve tool-event source order and always finalize EOS-delimited parsers. Never expose protocol payloads as assistant text.
- Treat Foundation Models streaming partials as cumulative text followed by at most one captured tool invocation: emit only text deltas, then make the tool event terminal so the caller can execute it and submit the result on the next turn.
- For local reasoning models, use the resolved model `reasoningConfig` and seed stream routing from the prepared prompt. Chat templates may prefill the opening reasoning delimiter, so generated output can begin inside reasoning and emit only the closing delimiter; parsers must also preserve partial delimiters across chunks.
- Treat tool parameters as a wire-schema boundary: normalize shorthand parameter types into a root `type: object` JSON Schema before inference, preserve already-complete schemas, and validate the encoded request shape against the provider.

## Testing Expectations

- Add or update unit/UI tests alongside behavioural changes. `FlowDownUnitTests` uses the Swift `Testing` library—author tests as `@Test func featureScenario_expectation()`.
- Keep `@Test` enablement predicates free of test events and side effects; optional fixture probes should return `false` when unavailable and only record failures from inside an enabled test.
- When a model workflow changes its structured-output contract, migrate its replay request/response fixtures in the same change and run `make test-online-e2e`. Route fixtures by their most specific semantic discriminator (such as a required tool name) before generic stream or transport fallbacks.
- Document manual verification steps whenever UI or integration flows lack automation.

## Security & Privacy

- Never hardcode secrets; rely on user-supplied keys and platform keychains.
- Validate new managers or services against the sanctioned singleton list above.
- Use `assert`/`precondition` to capture invariants during development.
- Audit persistence changes for privacy impacts before shipping.
- Preserve existing safeguards in `main.swift`: release builds disable stdout/stderr, strip debuggers, enforce signature validation, and ensure Catalyst sandboxing. Security hardening lives in `FlowDown/Backend/Security/`.
- Keep CloudKit identifiers, entitlements, and derived `CloudKitConfig.swift` generation in sync with deployment environments.

## Collaboration Workflow

- Craft concise, capitalized commit subjects (e.g. `Adjust Compiler Settings`) and use bodies to explain decisions or link issues (`#123`). Group related work per commit and avoid bundling unrelated refactors.
- Pull requests must include a summary, testing checklist, and before/after visuals for UI changes. Mention localization, generated assets (`FlowDown/DerivedSources`), or DevKit script updates when relevant.
- Capture key findings from external research in PR descriptions, and reference official docs or WWDC sessions when introducing new APIs.
- Keep architectural rationale and trade-offs close to the code (doc comments or dedicated markdown) when complexity grows.

## Code Review Guidelines

- Keep reviews pragmatic: prioritize reproducible, high-impact defects with clear user or data risk.
- Do not report intentional fail-fast patterns as bugs by default (`force unwrap`, `as!`, `try!`, `unowned`) when they protect explicit invariants. If an invariant can be violated, prefer explicit `precondition`/`assert` over silent fallbacks that hide corruption.
- Avoid recommending fixes for extremely low-probability race conditions unless impact is severe or reproduction is clear.
- Prefer root-cause fixes over broad defensive rewrites that mostly reduce crash visibility without improving correctness.
- Write findings as actionable items: trigger condition, concrete impact, minimal viable fix.
- For CI workflows that build, test, or archive: download the Metal toolchain before the first build step, keep Xcode selection aligned across build/test/archive/notarization, and treat Catalyst entitlement changes and Xcode upgrades as signing-profile migrations that need the notarization profile kept in sync.

## Localization Guidelines

- Source all user-visible strings from localization files instead of hardcoded literals. We ship en plus de, es, fr, ja, ko, and zh-Hans; every new key must land with all of them.
- Localization files (main app `FlowDown/Resources/`, plus `FlowDownTranslationProvider/` and `FlowDownWidgets/`) each carry `Localizable.xcstrings` and `InfoPlist.xcstrings`. They exceed 10k lines—regenerate through the scripts instead of editing the JSON by hand.
- Scripts, all under `Resources/DevKit/scripts/`:
  - `update_missing_i18n.py <file>` scaffolds new keys; add every language to the `NEW_STRINGS` dict first (`{"Key": {"de": …, "es": …, "fr": …, "ja": …, "ko": …, "zh-Hans": …}}`).
  - `check_untranslated.py <file>` reports entries missing or empty in any supported language.
  - `check_translations.py <file>` removes stale keys and verifies completeness across locales.

### Getting the key right

- `String(localized:)` accepts only a `String.LocalizationValue`, so interpolating inline is safe: `String(localized: "\(value) chances")` looks up `%lld chances`.
- The trap is any parameter that also accepts a plain `String`. `AlertViewController` declares both a `String.LocalizationValue` init and an `@_disfavoredOverload` `String` one, and a literal argument picks the `String` overload, which turns the *finished* text into the key—so an interpolated `title:`/`message:` looks up "…browser?\n\nhttps://example.com", finds nothing, and ships English. Wrap those in `String(localized:)` yourself.
- `ConfigurableKit` and `Indicator.present` take `String.LocalizationValue` directly; pass localization values to them without wrapping.
- Prefer `String.LocalizationValue`/`LocalizedStringResource` formatting over `String(format:)`; use `String(format:)` only for compatibility.
