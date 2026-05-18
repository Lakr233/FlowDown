# FlowDown

<p align="center">
  <a href="README.md">English</a> |
  <a href="/Resources/i18n/zh-Hans/README.md">简体中文</a>
</p>

FlowDown is a native AI chat client for Apple platforms, designed for speed, privacy, and power users. It provides a fluid, responsive interface to interact with a variety of AI models, right from your iPhone, iPad, and Mac.

![Preview](./Resources/SCR-PREVIEW.png)

## Download

[![App Store Icon](./Resources/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg)](https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198)

**About Pricing Update**

FlowDown is scheduled to become free this year. With growing community support and feature maturity, maintenance costs have decreased, allowing us to operate more efficiently. Before this transition, prices will be reduced in phases. All core chat features will remain free, with subscription fees applying only to future personalization options.

**Keep In Touch**

Join the public beta on [TestFlight](https://testflight.apple.com/join/StpMeybv) to try new features.

To get started, FlowDown includes complimentary access to select models. For more control, you can connect to self-hosted services or OpenAI-compatible providers. Learn more in our [documentation](https://flowdown.ai/docs/).

Join our community on [Discord](https://discord.gg/UHKMRyJcgc) for feedback and support.

## Features

- **Privacy First**:
  - **Nothing Collected**: FlowDown developers do not collect, store, or transmit any of your personal information or usage data. No telemetry, no crash reports.
  - **Zero Data Retention**: All content and configurations you create remain entirely on your device or your private iCloud.
  - **Verifiable Source**: The source code is open and available for audit. You can verify exactly what the app is doing.
- **Native Performance**:
  - **Built From Scratch**: Built entirely with Swift and UIKit. We open-sourced our chat interface as [LanguageModelChatUI](https://github.com/Lakr233/LanguageModelChatUI) for everyone.
  - **Rich User Experience**: Enjoy full Markdown rendering, syntax highlighting, and a buttery-smooth interface that makes interacting with AI a pleasure.
  - **Optimized for Apple Platforms**: Leverages Metal and MLX for efficient on-device inference and smooth UI performance.
- **Universal Compatibility**:
  - **OpenAI-Compatible APIs**: Connect to any service that supports the OpenAI chat completion API standard.
  - **Self-Hosted Models**: Easily connect to local inference servers like Ollama, LM Studio, or LocalAI.
- **Powerful Workflows**:
  - **Vision Support**: Interact with vision-capable models.
  - **Audio Support**: Send audio messages to compatible models using attachments.
  - **File Attachments**: Add files and documents to your conversations.
  - **Web Search**: Grant the AI access to real-time information from the web.
  - **Reusable Templates**: Save and quickly reuse your favorite prompts.
- **System Integration**:
  - **iCloud Sync**: Seamlessly syncs your conversations, settings, and custom models across all your Apple devices.
  - **Default Translation App**: Set FlowDown as your default translation app for seamless translation workflows.
  - **Shortcuts**: Deep integration with system Shortcuts for automating your workflows.
  - **Live Activity**: With sound effects enabled (customizable), you can use Live Activity to stream in the background.
  - **Model Exchange Protocol**: Share and import model configurations easily using the `.fdmodel` file format.

> **Note**: FlowDown is a Zero Data Retention (ZDR) app. While the app collects no data, our website uses anonymous analytics and Cloudflare security protection to maintain service quality.

## Special Notes

FlowDown is designed for users who want full control over their AI models and are willing to configure them manually.

Every model behaves differently based on its capabilities, deployment method, and hardware resources. You are responsible for configuring and testing each model you use. FlowDown provides the tools and interfaces—you provide the configurations.

For bulk management, FlowDown supports importing and exporting model configurations (`.fdmodel` files). You can script the generation of configuration files and import them all at once. Join our [Discord](https://discord.gg/UHKMRyJcgc) to discuss setups, but remember: community advice doesn't replace your own testing.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Lakr233/FlowDown&type=date&legend=top-left)](https://www.star-history.com/#Lakr233/FlowDown&type=date&legend=top-left)

## License

The source code is licensed under AGPL-3.0. You can find the full license text in the [LICENSE](./LICENSE) file.

The decoupled libraries used to build, or extracted from FlowDown are listed below with their respective licenses:

- [AlertController](https://github.com/Lakr233/AlertController) - MIT License
- [ColorfulX](https://github.com/Lakr233/ColorfulX) - MIT License
- [ListViewKit](https://github.com/Lakr233/ListViewKit) - MIT License
- [MarkdownView](https://github.com/Lakr233/MarkdownView) - MIT License
- [GlyphixTextFx](https://github.com/ktiays/GlyphixTextFx/) - MIT License
- [LanguageModelChatUI](https://github.com/Lakr233/LanguageModelChatUI) - MIT License

Please note that while the code is open source, the FlowDown name, icon, and artwork are proprietary. For commercial licensing inquiries, please contact us.

---

© 2025-2026 FlowDown Team (@Lakr233) All Rights Reserved.
## Sponsor

[LookInside](https://lookinside-app.com/) helps you inspect a running iOS or macOS app UI from your Mac.
