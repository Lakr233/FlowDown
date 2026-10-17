# Model Vision

## Overview

FlowDown supports visual understanding through local MLX or cloud vision models and can auto-generate descriptions, OCR, and QR results for text-only models. EXIF data is always stripped from images. When **Settings → General → Editor → Compress Image** is on (default), images are also resized to ~1024 px.

![Image compression setting](../../../res/screenshots/imgs/flowdown-chat-compression-feature-ui.png)

## Quick Start

1. Click the **＋** beside the composer, or drag/paste files into the input box.
2. On iOS/iPadOS, choose **Take Photo**, **Photo Library**, or **Files**; on macOS, pick any system-supported file.
3. Send your question/instruction and wait for the analysis result.

Thumbnails appear above the composer; tap or hover to preview, rename, or remove attachments.

![Add image from composer](../../../res/screenshots/imgs/mobile-chat-context-menu-functions.png)

## Configuration Checklist

- **Enable Vision capability**: Turn on Vision under **Settings → Model** (local) or on the cloud model edit page. Forcing Vision on unsupported models will fail.
- **Auxiliary Visual Model**: **Settings → Inference → Visual Assessment → Auxiliary Visual Model**. Used when the active chat model lacks Vision or when you need text fallbacks (descriptions/OCR/QR).
- **Skip Recognition If Possible**: **Settings → Inference → Visual Assessment**, default on. When the chat model has Vision, skipping sends the raw image; disable if you need OCR/backups or may switch to a text-only model.
- **Compress Image**: **Settings → General → Editor → Compress Image**, on by default to shorten uploads and remove EXIF data.

![Model capability configuration](../../../res/screenshots/imgs/ai-model-capability-configuration.png)
![Visual inference configuration](../../../res/screenshots/imgs/visual-inference-model-configuration.png)

## How It Works

### Dual Paths

- **Vision models**: receive the image plus any generated description.
- **Text-only models**: FlowDown calls the Auxiliary Visual Model to turn images into text before sending.

### When Preprocessing Runs

- Triggered when an image lacks a manual note and either:
  - the chat model does not support Vision, or
  - **Skip Recognition If Possible** is turned off.
- Skipped when the chat model supports Vision and the skip toggle is on.

### Processing Steps

- Generate a scene description
- Multilingual OCR extraction
- QR code detection and decoding

Results are written to the attachment’s text representation and persisted (non-ephemeral). Images are always EXIF-stripped; compression depends on the Compress Image toggle. If no Vision-capable Auxiliary Visual Model is configured and the chat model is text-only, the image will be skipped.

### Delivery to the Conversation

- **Vision chat model**: sends the raw image plus description.
- **Text-only chat model**: sends text representation only; if empty, the attachment is omitted.

## Prompting & Verification

- Be explicit: “Summarize this whiteboard,” “Compare these two screenshots,” or “Convert the table to CSV.”
- Reference filenames, e.g., “In invoice.png, what is the payment due date?”
- Use the message menu → **Raw Data** to confirm `[Image Description]`, `[Image Optical Character Recognition Result]`, and `[QRCode Recognition]`.
- If results look off, ask the model to re-check attachments or add more context and resend.
- Delete attachments from the message menu if you don’t want them kept.

### Local MLX Regression Checks

With a multi-image vision checkpoint such as Qwen3.5, enable **Vision** and
**Skip Recognition If Possible** to exercise the local model directly:

1. Run the model verification, then start a new conversation and send a text-only message.
2. Attach one image and ask about it using an ordinary prompt. Do not insert model-specific image tokens.
3. Send a text-only follow-up about that image, then attach two images and ask the model to compare them.
4. Confirm that the image turns and text-only turns complete without a placeholder/frame-count error.

![Rendering with attachments](../../../res/screenshots/imgs/flowdown-ai-content-rendering-process.png)
