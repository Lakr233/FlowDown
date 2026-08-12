# Changelog

This log tracks FlowDown version history and key changes.

## 5.0.2

- Retired the complimentary cloud model presets previously provided via OpenRouter and Pollinations AI. To use cloud models, bring your own API from any OpenAI-compatible provider; on-device MLX models and Apple Intelligence are unaffected.
- Replaced XML-based tool-call parsing with forced tool calls and added a contemplation capability for supported models.
- Merged conversation title and icon generation into a single pass, and the app now auto-selects a model when none is chosen.
- Persisted sidebar state across launches and softened the conversation cancellation message.
- Compressed tool and system prompts and completed the conversation API migration, removing legacy backend code.

## 4.11.2

- Made MCP server setup visible in Tool settings; tool calls are now cancellable and indicators are state-driven.
- Updated Markdown rendering, list components, SnapKit, and the local model stack.

## 4.10.3

- Merged web search into tool calls and remembered the Tools toggle across conversations.
- Rebuilt sidebar resizing so divider drags commit within a single frame, eliminating piled-up animations and flicker on Mac.
- Fixed blank-frame flicker while streaming and enabled deferred row sizing for smoother message updates.
- Fixed macOS release signing and restored Catalyst signing compatibility.

## 4.9.10

- Added Reminders tools so the assistant can create, query, update, complete, and delete items in Apple Reminders with permission, alongside grouped Calendar and Reminders toggles in Tool settings.
- Improved Calendar event creation through iCalendar parsing and Reminders filtering by due, alert, and completion dates.
- Restored the vertical scroll indicator in Mac Catalyst chat views and refined alerts and Markdown handling.

## 4.8.6

- Improved conversation metadata generation for better titles, icons, and organization.
- Improved Responses API handling for supported cloud models and strengthened memory context behavior.
- Fixed an import and unpacking issue that could affect model exchange workflows.
- Improved Mac Catalyst exit handling, added log clearing support, and improved local model download progress presentation.

## 4.7.9

- Overhauled memory with automatic extraction, cross-session context, and smarter conversation summarization that syncs across devices.
- Added speculative decoding to the local MLX engine for faster generation on supported devices.
- Improved web search, model tool, and Shortcut integration reliability.
- Fixed the Memory toggle behavior in settings and improved local model download progress alerts.

## 4.6.6

- Added a refreshed glass-style chat interface and a dedicated Mac Catalyst chat header.
- Added a Translate Text Shortcut that translates selected text with a chosen model into many target languages.
- Added a left-edge swipe gesture to open the sidebar on iOS and improved iPad Split View sizing.
- Fixed reasoning sections collapsing repeatedly while streaming and cleaned up empty assistant replies after tool calls.
- Refined settings controls for Live Activity, memory, and model tools.

## 4.5.9

- Added reasoning effort presets for supported models, giving quick control over how deeply a model thinks before answering.
- Added GPU support checks for local model inference and raised the app baseline to iOS 17.
- Updated Markdown rendering for better message display and improved database dependency handling.

## 4.4.10

- Added Live Activity support so streaming responses stay visible while FlowDown runs in the background, with audio feedback options for background inference.
- Added model evaluation sessions with an **Evaluate** action in model menus, plus import/export for evaluation results, chat templates, MCP servers, and models.
- Added a **New Chat (Use Once)** action to model menus.
- Enabled hardened runtime with checked allocations and hardened heap entitlements, and restored support for iOS 16.2 devices.

## 4.3.3

- Added glass effect support for the Catalyst helper with continuous corners.
- Improved model selection logic and placeholder styling.

## 4.2.9

- Introduced the FlowDown Translation Provider extension: translate text system-wide with your own models, with segmented results, multi-language support, and structured tool-based output.
- Added chat templates with iCloud sync and storage support, plus settings backup import/export.
- Added Model Exchange support and a refreshed welcome experience.
- Added a recovery mode for launch errors and a balanced emitter for smoother streaming output.
- Fixed a destructive database table error that could break sync, and added default model list endpoint detection for cloud models.

## 4.1.2

- You can now toggle Apple Intelligence in Inference settings with availability hints; default chat and auxiliary models update automatically.
- Cloud models let you choose the OpenAI request format (`/v1/chat/completions` or `/v1/responses`), with automatic endpoint detection and format-aware routing.
- Temperature presets now include a `Disabled (-1)` option so you can defer randomness to the provider.
- The cloud model editor adds quick actions (verify/export/duplicate) and safer endpoint, header, and body editors to simplify model maintenance.

## 3.10.11

### Memory System

- **Smart Recall**: Automatically pulls in relevant memories for more personalized replies.
- **Memory scope controls**: Choose the sharing window (past day/week/month or latest 15/30 items).

### Shortcuts Integration

- **Quick actions**: Launch FlowDown, send messages, and receive responses.
- **Content classification**: Classify text and images.
- **Smart summaries**: Turn long text into paragraphs or bullet lists.
- **Conversation tools**: Search chats, switch models, and create conversation links.
- **Image analysis**: Mixed image/text analysis (iOS 18+).

### Interface Polish

- **Swipe gestures**: Swipe list items to favorite, delete, or copy conversations.
- **Visual refinements**: Smoother animations and clearer hierarchy.

## 3.10.10

- Resolved recent stability regressions and improved adoption of upstream changes for the complimentary model pool.
- Polished CloudKit sync heuristics to reduce redundant fetches when switching devices quickly.
- Tuned release packaging ahead of macOS/iPadOS notarization changes.

## 3.10.8

Starting with 3.10, minor versions now use semantic versioning instead of build numbers for clarity.

- Added adaptive parsing for new Pollinations AI endpoints; new models no longer require app updates.
- Introduced custom request body editors so each model profile can use advanced inference parameters.
- Replaced the custom context menu with the native platform menu for a consistent experience across iOS and macOS.
- Redesigned cloud sync scheduling to reduce conflicts while working across multiple devices.

## 3.8

- **Cloud Sync**: Full CloudKit rollout with unified indicators, status glyphs in the sidebar, and Settings → Data Control hooks for scoped sync.
- **Data Management**: Export/import entire workspaces as signed `.zip` archives and clear iCloud data without affecting local caches.
- **Model Library**: Assign friendly nicknames to cloud models for easier switching.
- **Performance & Logging**: Faster deletion, smarter refresh pipelines, and a new Support logging console for troubleshooting.

## 3.6.419

- Early CloudKit build for advanced users. Upgrading migrates the database schema to V2 and cannot be rolled back.
- Paired with a cautionary GitHub release for manual installers.

## 3.6

- TestFlight rollout for iCloud sync, marked unstable with a data-loss warning; please back up before installing.
- TestFlight join link: `https://testflight.apple.com/join/StpMeybv`.

## 3.5

- Added a long-press tool menu on the editor bar so you can adjust tool availability without opening settings.
- Celebrated National Day with a limited free offer (ended 2025-10-06); earlier customers were invited to request redeem codes for other apps.

## 3.4

- Debuted a new immersive conversation interface.
- Enhanced Apple Foundation Model support, especially alongside Apple Intelligence on supported devices.
- macOS desktop release briefly delayed because of third-party compilation issues; the fix followed shortly after.

## 3.2

- Added per-model temperature configuration for finer control over creativity versus precision.
- Introduced initial Apple Foundation Model support and refreshed the MLX dependency for better performance.

## Legacy Releases (1.x–2.x)

<details>
<summary>Expand archived release history</summary>

## iOS 2.9 / macOS 2.9.1 (370)

### Fixes & Improvements

- **Editor and Rendering**
  - Fixed multiline equation rendering.
  - Fixed pointer device text selection on iPad.
  - Fixed a bug where streaming tasks were not cancelled properly after an error.

- **MCP Server**
  - Fixed a critical bug that blocked MCP server connections during edits.
  - Fixed an MCP services bug that dropped required fields while connecting.

- **General UI**
  - Corrected sidebar behavior on iPad.
  - Fixed menu placement in the model management page.

## 2.6 (357)

### Fixes and Improvements

- **MCP Server Connection**
  - Fixed a critical issue that could prevent connection when editing MCP servers.
  - Improved MCP connection management.

- **Task Management & Stability**
  - Fixed an issue where streaming responses were not cancelled properly after server errors.
  - Resolved several threading issues to improve stability.

- **User Interface (UI)**
  - Corrected menu placement in the model management page.
  - Fixed sidebar behavior on iPad.

## 2.2 (330)

### New Features

- **Added MCP Server Support**
  - Add, manage, and edit MCP servers.
  - Introduced `.fdmcp` files with drag-and-drop and file picker support.

- **Editor and UI Enhancements**
  - The editor now auto-focuses after creating a new conversation.
  - MarkdownView supports scrolling while selecting text.
  - ToolHintView layout and response speed optimized.

- **Other**
  - Support for custom brand names.

### Fixes and Improvements

- **Bug Fixes**
  - Fixed editor focus on Mac Catalyst.

## 2.0 (324)

### New Features

- **Global Search:** Search for keywords across all conversations.

### Improvements

- **Rewritten Markdown Text Engine:** Rebuilt the core text engine with:
  - Major performance gains.
  - Better math rendering compatibility for Math Functions.
  - Improved code highlighting without blinking.

### Bug Fixes

- Fixed blinking highlights and table views during streaming.
- Fixed text copying while a response was streaming.

## 1.26 (262)

This update introduces several new features and addresses key issues to enhance your experience.

### New Features

- **AI-Powered Template Rewriting**: Use AI to rewrite chat templates with extra instructions.
- **Template Management**:
  - Rearrange chat templates with drag and drop.
  - Export and open chat template files.
- **Favorite Conversations**: Mark conversations as favorites for quick access.
- **Drag and Drop Export**: Export `fdmodel` files by dragging and dropping.

### Improvements

- **Sidebar Enhancements**:
  - Collapse the sidebar on macOS.
  - Adjust sidebar width on iPad and macOS.
  - Keep the sidebar persistently visible on iPad for easier navigation.

### Bug Fixes

- **UI**: Fixed shadows in the chat view.

## 1.25 (250)

- Added streaming support and prevented rejection from FoundationModels (@at-wr).
- Improved iPad experience with Magic Keyboard (@at-wr).
- Set a default model identifier for new conversations when none is provided (@at-wr).
- Added custom decoding for CloudModel to handle optional properties (@at-wr).

## 1.24 (242)

- Included `@generable` Data Struct FoundationModels (@at-wr).
- Fixed multiple crashes when creating a new chat from compressor (@at-wr).

## 1.24 (241)

- Added compress to new chat.
- Added rewrite action.
- Added redo for #16.
- Improved multi-line LaTeX support in prompts.

## 1.23 (231)

- Added support for custom headers in cloud model.
- Fixed escape key responsiveness.
- Fixed unwanted shake behavior.
- Fixed a bad merge that lost the HTTP-Referer header.
- Updated keyboard logic.

## 1.22 (223)

- Minor fixes and improvements.

## 1.22 (222)

- Minor fixes and improvements.

## 1.21 (210)

- Enhanced PDF import with dual modes (text extraction or image conversion).
- Improved error handling for large files.
- Added keyboard navigation shortcuts for quick chat switching.
- Added menu bar template integration for direct template access.
- Added template menu to Menu Bar (@at-wr).
- Added shortcuts to navigate between conversations (@at-wr).

## 1.20 (200/201/202)

**Chat Template System** 📋

- New reusable chat templates for faster workflows.
- AI-generated templates from existing conversations.
- Intuitive template editor with creation and deletion.
- Quick preset selection when starting new chats.

**General Improvements**

- Fixed missing entitlements for efficient iOS/iPadOS performance.
- Fixed on-device visual language model support.
- Added Gemma3 model support.
- Added HTML preview for generated code.

## 1.19 (190)

- Added new menu items.
- Added a welcome log for first-time app launch.
- Improved OpenRouter integration.
- Fixed auto-focus issues when creating new chats on Mac.
- Improved background processing.
- Fixed reasoning content not updating in some cases.
- Fixed logical errors related to model tools.

Thanks to the following contributors:

- @at-wr
- @Zach677

## 1.13 (130)

- Fixed keyboard shortcuts for copying text in code view.
- Fixed incorrect cursor display when selecting text.
- Fixed unresponsive drag gestures on the first and last lines of text.
- Fixed code syntax highlighting not applying.
- Fixed reasoning requests being added to auxiliary tasks.
- Added an option to use developer role when needed.
- The app can now be opened via `flowdown://` protocol.
- The app can now open model files in place.

## 1.11

- Fixed incorrect model identifiers when copying models.
- Fixed math content rendering.
- Fixed menu disappearing when right-clicking the conversation list.
- Fixed documents not being indexed after web search.

## 1.10 (101/102)

- Improved the visual task scheduler with an option to skip auxiliary tasks for vision-native models.
- Fixed editor lag when processing large images.
- Fixed editor inability to restore editable content.
- Improved auxiliary task structure and execution speed.
- Improved data flow for web search when tool calling is enabled.
- Fixed missing reasoning content in image recognition tasks.
- Added support for OpenRouter model inference tokens.

## 1.9 (90)

- Added preliminary math content support.
- Added LaTeX math formula display.

## 1.7 (70)

- Fixed Qwen3 local model support.
- Updated MLX model manifest structure for compatibility.
- Temporarily disabled local vision while waiting for upstream fixes.
- FlowDown is now fully open source so you can verify privacy protections yourself.

## 1.6 (60)

- Improved local model support.
- Fixed multiple known issues.

## 1.5 (50)

- Fixed issues when pasting content.
- Fixed web search phase indicator.
- Fixed wrong return key title in the input box.
- Fixed a bug where multiple tool calls were received simultaneously.
- Added support for connecting to locally hosted LLMs via OLLAMA and LM Studio.

## 1.4 (49)

- Fixed a crash when using the location tool with location services disabled.

## 1.4 (47/48)

- Fixed table border color updates.
- Fixed a crash when quickly deleting messages.
- Allowed sending empty messages when attachments are present.
- Added direct text selection.

## 1.3 (44)

- Fixed crashes with certain reasoning models.
- Fixed content unexpectedly showing as reasoning.
- Fixed chat list element positioning errors.
- Fixed endpoints that did not support usage statistics.
- Fixed unsaved content after crashes.
- Fixed code blocks that could not open the details page in the Hugging Face download screen.
- Fixed code blocks and tables not using correct information in edge cases.
- Fixed logical errors when interrupting inference.
- Fixed deleting error messages during retries.
- Disabled local model functionality on devices that do not support MLX.
- Adjusted the order and logic of several menus.
- Adjusted logic for deleting conversation content.
- Adjusted logic for editing conversation content.
- Added an option to send messages with Command + Enter.
- Added an option for long-press to create a new line.
- Added an option to save replies as images.
- Removed the temporary chat option.

## 1.2 (36/37/42)

- Added image export to save chat content as images.
- Added the ability to end conversations at any time.
- Improved web search with a deduplication algorithm for results.
- Fixed inconsistent text size rendering in supplement views.
- Refactored code and resolved multiple known issues.

## 1.1 (35)

- Fixed an issue where extracted image information was not stored correctly.
- Fixed an issue where the system prompt was not updated correctly.
- Fixed an issue where tool calls could trigger server errors.

## 1.0 (32/33)

First release to the App Store.

- Changed the app icon.
- Fixed the DeepSeek model not supporting out-of-order system prompts.
- Fixed retries not using the correct model.
- Fixed tool call failures by removing the `minLength` parameter unsupported by some models.
- Fixed the model not using the latest time.
- Adjusted prompts used by the tool.
- Added an option for 64k context length.

## 1.0 (28)

- Cloud models now support tool use.
- Added a right-click/long-press shortcut menu to the model selector.
- Improved tool call status display, and some tools show call details.
- Added an option for 64K context.
- Fixed crashes caused by undo operations.
- Improved handling when the model is unavailable.
- Fixed permission issues and improved error messages.
- Optimized data export logic and logging.
- Improved the pre-dialogue check mechanism for stability.

## 1.0 (20)

- Fixed menu event responses.
- Fixed code view height mismatches.
- Fixed the model name not updating as expected.
- Improved the long-press interaction in the conversation list.
- Improved inference engine efficiency.
- Improved the URL opening mechanism and added security warnings.
- Reduced network crawler resource usage.
- Replaced widget icons.

</details>
