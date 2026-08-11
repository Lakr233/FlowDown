# Basic Usage

FlowDown provides an immersive chat interface, supports local models, and can sync data via iCloud. This guide combines the first-chat steps with everyday usage.

## Start your first conversation

1. Open FlowDown and click **New Conversation** in the sidebar; the composer appears at the bottom.
2. Choose a model below the composer: Apple Intelligence, a local MLX model, or a cloud profile you configured.
3. Above the composer, toggle **Tools** (calendar/location/memory/MCP) and **Web Browsing** as needed; enable **Memory** to write highlights to long-term memory.
4. Type your message. `Shift + Enter` adds a new line. Drag files to attach text/Markdown, PDF, PNG/JPEG/WebP/HEIC, or audio (m4a/wav; others auto-transcoded).
5. Press `Enter` (or tap send) to send. Stop a reply via the stop button or the conversation menu in the top right.

![Conversation view](../../../res/screenshots/imgs/conversation-main-view.png)

## Manage conversations

- The list on the left shows all conversations. Click to switch; on touch devices you can swipe, and right-click/long-press to open the quick menu.
- The assistant auto-generates a title and icon after the first reply. Use the quick menu to **Rename** or **Change Icon**.
- Use **Duplicate** to create a copy of a conversation.
- To adjust tools, web browsing, or system prompts for a conversation, open **Conversation Settings** from the quick menu.

![Conversation quick menu](../../../res/screenshots/imgs/conversation-set-new-icon.png)

## UI & rendering

- Replies support full Markdown (tables, code blocks, quotes).
- In the message menu, **Raw Data** shows the full prompt, including system instructions and attachment context; you can also copy/export/archive here.

## Cross-device sync

FlowDown stores data locally and can optionally sync through CloudKit.

- Turn on **Settings → Data → iCloud Sync** on each device. The sidebar shows the latest sync status and pending changes.
- After adding a new device or resolving conflicts, toggle iCloud Sync off and on to refresh data.
- You can export a backup anytime via **Settings → Data → Export Database**. Restoring replaces all local data with the imported backup.

![Sync scope on iPad](../../../res/screenshots/imgs/configuring-sync-scope.png)

## Next steps

- Use built-in tools: see [Tools](../capabilities/tools_automation.md) and [Web Search](../capabilities/web_search.md).
- Explore scenarios such as [Calendar Workflow](../guides/calendar_workflow.md).
- Tune inference and models in [Cloud Models Setup](../models/cloud_models_setup.md) and [Inference Configuration](../models/inference_configuration.md).
