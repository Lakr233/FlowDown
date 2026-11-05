# Auxiliary Tasks

Auxiliary tasks are background chores such as titling conversations, choosing a cover icon, and running lightweight work without interrupting the main chat. They always run on the conversation's chat model, so there is nothing to configure.

## What Auxiliary Tasks Do

- **Title generation** – Creates concise, descriptive titles for the conversation list.
- **Icon synthesis** – Chooses an emoji-style icon that reflects the conversation topic.
- **Web search prep** – When browsing is enabled, decides whether to search and emits up to three queries via the Web Search tool before the main reply.
- **Memory and summaries** – Extracts memories and keeps conversation summaries up to date after a reply.

## When They Run

- **Before the reply**
  - When browsing is enabled, the chat model and Web Search tool decide `search_required` and generate queries.
- **After the reply**
  - Title and icon refresh run only while auto-rename is on. Manual title/icon edits or manually generating a new title/icon from the conversation menu turn auto-rename off; the same menu lets you regenerate on demand.

## Model Requirements

Titles and icons are generated through a tool call, so they need a chat model with tool calling. With any other model the conversation keeps its existing title and icon.

Auxiliary tasks use the same model as the conversation, so they are billed to that model. To change which model runs them, switch the conversation's model.

## Best Practices

- If auto titles/icons look off, switch to a stronger chat model or regenerate from the conversation menu; manual edits disable further auto-renames.

This document may lag behind rapid code changes. When in doubt, rely on the in-app settings descriptions and the current release notes.
