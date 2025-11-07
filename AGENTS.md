# FlowDown Agent Guide

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview
FlowDown is a Swift-based AI/LLM client for iOS and macOS (Catalyst) with a privacy-first mindset. The Xcode workspace hosts the app plus several Swift Package Manager frameworks that power storage, editing, and model integrations.

## Environment & Tooling
- Prefer working through `FlowDown.xcworkspace` so app and frameworks build together with the correct schemes.
- Use `make` for release archives; clean artifacts with `make clean` (see `Resources/DevKit/scripts/archive.all.sh`).
- Reach for `xcbeautify -qq` when running `xcodebuild` locally to keep logs concise.

## Platform Requirements & Dependencies
- Target platforms reflect framework minimums: iOS 17.0+, macCatalyst 17.0+.
- Toolchain: Swift 5.9+ is required to satisfy package manifests (`swift-tools-version: 5.9`).
- Core dependencies (via SwiftPM): MLX/MLX-examples for on-device models, WCDB for storage, MarkdownView for rendering, and dedicated UI/editor libraries like RichEditor and RunestoneEditor.
- MLX GPU support is automatically detected and disabled in simulator/x86_64 builds (see `main.swift`)

## Project Structure
- `FlowDown.xcworkspace`: Entry point with app and frameworks.
- `FlowDown/`: Application sources divided into `Application/` (entry surfaces), `Backend/` (conversations, models, storage, security), `Interface/` (UIKit), `PlatformSupport/` (macOS/Catalyst glue), and `BundledResources/` (curated assets shipped with the app).
- `Frameworks/`: Shared Swift packages (`ChatClientKit`, `Storage`, `RichEditor`, `RunestoneEditor`, `Logger`). Each package owns its manifest and dependency graph.
- `Resources/`: Shared assets, localization collateral, privacy documents, and DevKit utilities.
- `Playgrounds/`: Exploratory prototypes; do not assume production readiness.

## Build & Run Commands
- Open the workspace: `open FlowDown.xcworkspace`.
- Debug builds:
  - iOS: `xcodebuild -workspace FlowDown.xcworkspace -scheme FlowDown -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15'`
  - macOS Catalyst: `xcodebuild -workspace FlowDown.xcworkspace -scheme FlowDown-Catalyst -configuration Debug -destination 'platform=macOS'`
- Release archive (both platforms):
  - `make` to archive (runs `Resources/DevKit/scripts/archive.all.sh`)
  - `make clean` to reset build artifacts
- Package-only verification: `swift build --package-path Frameworks/<Package>`
- When running CI-style builds, prefer `xcodebuild -workspace FlowDown.xcworkspace -scheme FlowDown -configuration Debug build`
- Archive script automatically commits changes and bumps version before building
- Use `python3 Resources/DevKit/scripts/check_translations.py FlowDown/Resources/Localizable.xcstrings` for localization validation, fix any missing using python script too.

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
- Backend services are organized by domain: `ChatTemplate`, `Conversation`, `Model`, `ModelTools`, `MCPService`, `Storage`, `Security`, `UpdateManager`
- Key initialization sequence in `main.swift`: Storage → ModelManager → ModelToolsManager → ConversationManager → MCPService → UpdateManager (macOS/Catalyst only)

## Testing Expectations
- Add or update unit/UI tests alongside behavioural changes. No `FlowDownTests` target ships today; introduce new suites under sensible targets (e.g., create an app test target or add tests within `Frameworks/<Package>/Tests`) when expanding coverage.
- Name tests using `testFeatureScenario_expectation`.
- Run `xcodebuild test -workspace FlowDown.xcworkspace -scheme FlowDown` for end-to-end coverage once a test target exists, or `swift test --package-path Frameworks/<Package>` for package scope.
- Document manual verification steps whenever UI or integration flows lack automation.

## Security & Privacy
- Never hardcode secrets; rely on user-supplied keys and platform keychains.
- Validate new managers or services against the sanctioned singleton list above.
- Use `assert`/`precondition` to capture invariants during development.
- Audit persistence changes for privacy impacts before shipping.
- Remember existing safeguards: Catalyst builds run sandbox checks, release builds enforce signature validation, and anti-debugging guards run during startup.

## Documentation & Knowledge Sharing
- Capture key findings from external research in PR descriptions so future contributors can trace decisions.
- Reference official docs, WWDC sessions, or sample projects when introducing new APIs.
- Keep architectural rationale and trade-offs close to the code (doc comments or dedicated markdown) when complexity grows.

## Collaboration Workflow
- Craft concise, capitalized commit subjects (e.g., `Adjust Compiler Settings`) and use bodies to explain decisions or link issues (`#123`).
- Group related work per commit and avoid bundling unrelated refactors.
- Pull requests must include a summary, testing checklist, and before/after visuals for UI changes. Mention localization or asset updates when relevant.
- Tag reviewers responsible for the affected modules and outline any follow-up tasks or risks.

## Localization Guidelines
- Always use `String(localized: "text")` for user-facing strings instead of hardcoded text
- Add new localized strings to `FlowDown/Resources/Localizable.xcstrings` when introducing new UI text
- Run `python3 Resources/DevKit/scripts/update_missing_i18n.py FlowDown/Resources/Localizable.xcstrings` after adding strings, then audit results with `check_translations.py`
- Follow existing localization patterns and maintain consistency with the codebase
- Adding new localized stirngs requires you to use an script above, you can edit the script. Avoid manual edits to localization files.
