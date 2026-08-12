# 浮望 (FlowDown)

<p align="center">
  <a href="../../../README.md">English</a> |
  <a href="/Resources/i18n/zh-Hans/README.md">简体中文</a>
</p>

浮望 (FlowDown) 是一款为 Apple 平台精心打造的原生 AI 对话客户端，追求极致的速度与流畅体验，并始终将你的隐私放在首位。无论是在 iPhone、iPad 还是 Mac 上，浮望都能为你提供与 AI 模型交互的绝佳体验。

![Preview](../../../Resources/SCR-PREVIEW.png)

## 下载

[![App Store Icon](../../../Resources/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg)](https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198)

**关于定价更新**

FlowDown 计划于今年转为免费应用。随着社区支持的增加和功能成熟，维护成本已降低。在此之前，我们将分阶段下调价格。核心聊天功能将始终免费，订阅费用仅适用于未来的个性化选项。

**保持联系**

加入 [TestFlight](https://testflight.apple.com/join/StpMeybv) 公开测试体验新功能。

FlowDown 内置了免费模型供您快速上手。如需更多控制权，可连接自托管服务或 OpenAI 兼容提供商。详情请参阅[在线文档](https://flowdown.ai/docs/)。

欢迎加入 [Discord](https://discord.gg/UHKMRyJcgc) 社区交流反馈。

## 特色功能

- **隐私保护**：
  - **无数据收集**：我们不收集、存储或传输您的任何个人信息或使用数据。无遥测，无崩溃报告。
  - **零数据留存**：您创建的所有内容和配置完全保留在您的设备或您的私人 iCloud 上。
  - **开源可审计**：源代码公开可用。您可以确切地验证应用程序正在做什么。
- **原生性能**：
  - **从零构建**：完全使用 Swift 和 UIKit 构建。我们将聊天界面以 [LanguageModelChatUI](https://github.com/Lakr233/LanguageModelChatUI) 开源供所有人使用。
  - **极致体验**：完整的 Markdown 渲染、代码语法高亮，以及如丝般顺滑的交互界面。
  - **为 Apple 平台优化**：利用 Metal 和 MLX 实现高效的端侧推理和流畅的 UI 性能。
- **广泛兼容**：
  - **OpenAI 兼容 API**：连接到任何支持 OpenAI 聊天补全 API 标准的服务。
  - **自托管模型**：轻松连接到 Ollama、LM Studio 或 LocalAI 等本地推理服务器。
- **强大工作流**：
  - **视觉支持**：与支持图像理解的多模态模型进行互动。
  - **音频支持**：使用附件向兼容的模型发送音频消息。
  - **文件附件**：在对话中轻松添加文件和文档。
  - **联网搜索**：授权 AI 访问互联网，获取实时信息。
  - **对话模板**：保存并快速复用你最喜欢的提示词。
- **系统集成**：
  - **iCloud 同步**：在你的所有 Apple 设备之间无缝同步对话、应用设置和自定义模型。
  - **默认翻译应用**：将 FlowDown 设置为默认翻译应用，实现无缝翻译工作流。
  - **快捷指令**：与系统快捷指令深度集成，自动化你的工作流程。
  - **实时活动**：开启可自定义的音效后，可在后台使用实时活动查看串流的输出。
  - **模型交换协议**：使用 `.fdmodel` 文件格式轻松共享和导入模型配置。

> **注意**：FlowDown 是一款零数据留存 (ZDR) 应用。应用本身不收集数据，我们的网站仅使用匿名统计和 Cloudflare 安全防护以维护服务质量。

## 特别说明

浮望面向希望完全掌控 AI 模型配置、并愿意手动配置的用户。每个模型的表现因其能力、部署方式和硬件资源而异。你需要对自己配置和使用的每个模型负责。浮望提供工具和接口——配置由你负责。

如需批量管理，浮望支持导入和导出模型配置文件（`.fdmodel` 格式）。你可以编写脚本批量生成配置文件，然后一次性导入。欢迎加入我们的 [Discord](https://discord.gg/UHKMRyJcgc) 讨论配置方案，但请记住：社区建议不能替代你自己的测试验证。

## 许可证

项目源代码基于 AGPL-3.0 许可证。你可以在 [LICENSE](../../../LICENSE) 文件中找到完整的许可证文本。

用于构建浮望或从中提取的解耦库如下，其各自许可证如下：

- [AlertController](https://github.com/Lakr233/AlertController) - MIT License
- [ColorfulX](https://github.com/Lakr233/ColorfulX) - MIT License
- [ListViewKit](https://github.com/Lakr233/ListViewKit) - MIT License
- [MarkdownView](https://github.com/Lakr233/MarkdownView) - MIT License
- [GlyphixTextFx](https://github.com/ktiays/GlyphixTextFx/) - MIT License
- [LanguageModelChatUI](https://github.com/Lakr233/LanguageModelChatUI) - MIT License

请注意，项目代码遵循开源许可，但“浮望”的名称、图标及相关视觉设计为专有资产。如需商业授权，请与我们联系。

---

© 2025-2026 FlowDown 团队 (@Lakr233) 保留所有权利。
