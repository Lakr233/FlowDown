# Inference Configuration

One place for context windows, temperature/sampling, and Reasoning/Thinking toggles. Settings apply per model profile and take effect immediately (synced via iCloud and backups).

For local, on-device inference, FlowDown supports MLX model profiles only. GGUF and Core ML files are not supported as direct local model formats in the app.

## Where to edit

1. Go to **Settings → Model** and pick a profile.
2. Adjust items under **Inference** and **Networking (Optional)**, then save.

## Core parameters

- **Context Length**: how much history and attachments a model can keep. If the estimate exceeds the limit, FlowDown trims the oldest non-system messages; if nothing can be trimmed, the request is cancelled. Presets: 4k/8k/16k/32k/64k/100k/200k/1M/Infinity.
- **Creativity (Temperature)**: higher = more diverse wording; lower = stable/deterministic. Start at 0.5–0.75 for general Q&A; 0–0.25 for code/facts. Use presets (e.g., Humankind, Precise) as shortcuts.
- **Sampling keys**: add `top_p`, `top_k`, `presence_penalty`, `frequency_penalty`, or `repetition_penalty` in JSON/editor view. Change one knob at a time with small steps.

## Advanced reasoning (Reasoning / Thinking)

For providers that support chain-of-thought keys in the request body:

1. Open **Additional Body Fields** and use **Reasoning Parameters** (•••).
2. Insert one key: `reasoning` / `enable_thinking` / `thinking_mode` / `thinking`.
3. Pick a **Reasoning Budget** preset (512/1024/4096/8192 tokens). FlowDown writes `reasoning.max_tokens` or `thinking_budget` based on the key.
4. Add provider-specific switches or tracing fields in the same JSON object if needed.

> If multiple reasoning keys are present, the editor will prompt you to keep one.

## Context and tools

- Counted toward context: global/per-conversation system prompts, recent messages, attachment text/media, web search results, tool definitions and outputs, reasoning fields.
- Media estimates: images ~512 tokens; audio ~1024 tokens. When trimmed, FlowDown shows “Some messages were removed to fit the model’s memory.”
- Control usage: lower search page limits or MCP result counts, compress long chats, or move recurring facts into Memory.

## Provider & networking options

- **Headers / Body**: set auth, tenant IDs, reasoning toggles, or sampling keys in **Request headers** and **Additional body fields**. Keep JSON valid.
- **Content format**: `chatCompletions` vs `responses` must match the endpoint, or calls will fail.
- **Capabilities**: declare Tool/Vision/Audio/Developer role to expose the right UI toggles and control attachment return paths.

## Related links

- For endpoint, header/body layout, see [Cloud Models Setup](./cloud_models_setup.md#advanced-custom-enterprise-setup).
- For conversation compression or prompt hygiene, see [System Prompts](../configuration/system_prompts.md) and [Memory Management](../settings/memory_management.md).
