# Chat Flow

When you press **Send**, FlowDown coordinates system prompts, attachments, tool calls, and model reasoning to complete a conversation. Understanding this flow helps you debug prompts, optimize settings, and find performance bottlenecks.

## 1. Composition & Validation

1. **Merge context**: Combine your draft with history. Existing system prompts, past user/assistant messages, and attachments stored in the library are converted into this request.
2. **Capability check**: Verify the current model supports the needed abilities (vision, tool calling, auxiliary tasks). If not, FlowDown will suggest switching models or adjusting settings.
3. **Inject dynamic instructions**:
   - Runtime info (model name, current time, locale).
   - Search mode hints when browsing is enabled (based on sensitivity presets).
   - Long-term memory summaries and memory-tool guidance when those tools are enabled.
4. **Append user input** after the latest system instructions so the model can read your final intent.

## 2. Pre-Actions

Before contacting the model, FlowDown performs lightweight tasks to prepare context:

- **Attachment extraction** – Parses PDFs, images, and text files into summaries. Images go straight to vision models; no separate recognition step runs.
- **Template & memory recall** – If enabled, injects long-term memory summaries and memory-tool guidance; existing system prompts (including templates) are inherited from history.
- **Web search planning** – When browsing is on and tool calling is off, FlowDown asks the model for up to three short queries based on recent turns and attachment text. The model can decide not to search or automatically fetch results and attach them as `<web_document id="n">` snippets for citation.
- **Tool environment setup** – Gathers enabled tools. When browsing is off, search tools are filtered out; if MCP servers are enabled, connections are warmed up.

**Note**: All the above steps run locally. Network access occurs only when browsing/search is on or when tools execute later.

## 3. Execution Loop

With the state ready, FlowDown enters an interactive loop with the selected model:

1. **Persist data** – Save the user message and attachments (skipping storage in ephemeral mode). Add image captions when needed and record web-search placeholders.
2. **Trim context** – Estimate tokens for the full request (including tool definitions). If over the limit, remove the oldest non-system messages first and indicate that trimming occurred.
3. **Send prompt** – Stream the prepared messages plus tool definitions.
4. **Monitor output** – Show reasoning traces, collect tool-call requests, and accept model-generated images (stored as user attachments with captions).
5. **Handle tool calls** – Validate and run tools. Web-search tools inject fetched documents; other tools may return images or audio (audio is transcoded). Very long text is truncated at 64k before returning to the model.
6. **Continue** – The model can keep reasoning or trigger more tools until no pending calls remain.

You can stop at any time with the stop button. The long-press quick menu also lets you temporarily disable tools.

## 4. Response Assembly

- Combine final text, code blocks, inline images, and tool outputs into the renderer (web-search references stay numbered).
- Clean up formatting (Markdown rendering, code beautification, LaTeX highlighting) and fix link references from web results.
- Collapse or expand reasoning sections based on your preferences (see **Settings → Chat Interface**).

## 5. Persistence & Sync

- Messages, attachments (including auto-generated image captions, web documents, and tool-produced media), and tool outputs are written to the local database.
- If iCloud is on, changes enter the CloudKit queue; otherwise they stay local.
- Undo/redo stacks are updated so you can return to drafts or undo actions.

## 6. Auxiliary Tasks

- If auto-rename is enabled, the chat model refreshes conversation titles and icons.
- Diagnostic logs are recorded for export via **Settings → Support**.
- Completion signals are sent to Shortcuts, MCP, calendar, and other automations.

You can view details at any time: in the message menu, choose **View Raw** to see the exact prompt sent to the model; tool call records also appear in the reasoning section.
