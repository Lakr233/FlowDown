# Apple Shortcuts

FlowDown provides App Intents so you can automate common tasks from the Shortcuts app, Spotlight, widgets, or Siri. Install FlowDown on iOS, iPadOS, or macOS to make these actions available everywhere.

**Heads-up:** Apple’s Shortcuts runtime enforces a strict execution time limit (about 30 seconds). Use a lighter model or lower the reasoning budget when chaining longer flows.

## Getting Started

1. Open **Shortcuts** and tap **+** to create a new shortcut.
2. Search for "FlowDown." All available intents appear under the FlowDown heading.
3. Choose an intent, set its parameters (model, message, files, audio, candidates), and chain it with other actions such as Calendar, Reminders, or Files.
4. Add the shortcut to the Home Screen or assign a Siri phrase for quick access.

## Generation & Media Intents

| Intent                                                                     | Description                                                                                              | Key Parameters                                                                        |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **Generate Model Response**                                                | Sends a prompt, can save the exchange as a new conversation, and can enable memory tools when supported. | `Model` (optional), `Message`, `Save to Conversation`, `Enable Memory Tools`          |
| **Generate Model Response (Can Send Image)** _(iOS/iPadOS 18+, macOS 15+)_ | Sends a prompt with an optional image; requires a vision-capable model.                                  | `Model`, `Message`, `Image` (optional), `Save to Conversation`, `Enable Memory Tools` |
| **Transcribe Audio** _(iOS/iPadOS 18+, macOS 15+)_                         | Converts an audio file to text with an audio-capable model and can store the transcript.                 | `Model`, `Audio`, `Language Hint` (optional), `Save to Conversation`                  |

## Classification Intents

| Intent                                           | Description                                                                                   | Key Parameters                      |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------- | ----------------------------------- |
| **Classify Content**                             | Picks the best candidate label for the provided text; if unsure, returns the first candidate. | `Model`, `Content`, `Candidate A-D` |
| **Classify Image** _(iOS/iPadOS 18+, macOS 15+)_ | Classifies an image against the provided candidates; requires a vision-capable model.         | `Model`, `Image`, `Candidate A-D`   |

## Writing Utilities

| Intent                             | Output                                                        |
| ---------------------------------- | ------------------------------------------------------------- |
| **Summarize Text**                 | Returns a concise paragraph summarizing the provided content. |
| **Summarize Text as List**         | Returns bullet points that capture the main ideas.            |
| **Improve Writing - Professional** | Rewrites text with a confident, professional tone.            |
| **Improve Writing - Friendly**     | Rewrites text with a warm, approachable tone.                 |
| **Improve Writing - Concise**      | Trims the text to its essentials while preserving intent.     |

All writing intents accept a `Model` parameter so you can route shortcuts to Apple Intelligence, local MLX models, or configured cloud profiles.

## Conversation & Navigation Intents

| Intent                         | Description                                                                                                 | Key Parameters                            |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Create Conversation Link**   | Builds a `flowdown://new/<message>` deep link for launching a new chat via Open URL.                        | `Initial Message`                         |
| **Fetch Last Conversation**    | Returns the full transcript (including reasoning) of the most recent conversation; requires device unlock.  | -                                         |
| **Search Conversations**       | Searches saved chats by keyword (or recent when empty) and returns formatted summaries; limit 1-50 results. | `Keyword`, `Result Limit`                 |
| **Create New Conversation**    | Creates an empty conversation and can immediately switch to it.                                             | `Switch to Conversation`                  |
| **Fill Conversation Message**  | Stages text, images, and audio in the selected conversation editor; pair with Show/Show & Send.             | `Conversation`, `Text`, `Images`, `Audio` |
| **Show Conversation**          | Opens FlowDown to the specified conversation without sending.                                               | `Conversation`                            |
| **Show and Send Conversation** | Opens FlowDown and sends the staged message.                                                                | `Conversation`                            |
| **Open FlowDown**              | Launches the app without additional actions.                                                                | -                                         |

## Model Management Intents

| Intent                     | Description                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| **Set Conversation Model** | Sets the default model for new conversations and as the fallback when other intents do not specify one. |

## Tips

- Toggle **Save to Conversation** when you want history; FlowDown creates a "Quick Reply" chat with attachments and reasoning.
- Turn on **Enable Memory Tools** to inject proactive memory context and let the model write updates when tools are available.
- Pick vision- or audio-capable models for image or audio shortcuts; remove attachments if the chosen model lacks support.
- Chain **Fill Conversation Message** -> **Show and Send Conversation** to deliver staged prompts; add **Create New Conversation** first when you need a fresh thread.
- Combine **Create Conversation Link** with **Open URL**, and check Shortcuts logs for issues such as missing models or empty messages.

For MCP automation, see [MCP Tools](../capabilities/mcp_integration.md).
