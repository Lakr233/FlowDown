//
//  WelcomePageViewController+Configuration.swift
//  FlowDown
//
//  Created by qaq on 8/12/2025.
//

import SnapKit
import SwifterSwift
import UIKit

extension WelcomePageViewController {
    struct Configuration {
        var title: String.LocalizationValue
        var highlightedTitle: String.LocalizationValue
        var subtitle: String.LocalizationValue
        var buttonTitle: String.LocalizationValue
        var accentColor: UIColor
        var icon: UIImage
        var features: [Feature]
    }

    struct Feature {
        var icon: UIImage
        var title: String.LocalizationValue
        var detail: String.LocalizationValue
    }
}

extension WelcomePageViewController.Configuration {
    static var `default`: Self {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "This App"

        return .init(
            title: "Welcome to",
            highlightedTitle: "\(displayName)",
            subtitle: "Your privacy-first AI workspace. Blend local intelligence with powerful cloud models in one seamless experience.",
            buttonTitle: "Get Started",
            accentColor: .accent,
            icon: .avatar,
            features: [
                // MARK: - Core Philosophy (核心理念)

                .init(
                    icon: UIImage(systemName: "lock.shield.fill")!,
                    title: "Privacy First",
                    detail: "No data collection. Your chats and keys stay on your device.",
                ),
                .init(
                    icon: UIImage(systemName: "icloud.fill")!,
                    title: "iCloud Sync",
                    detail: "Seamlessly sync conversations across iPhone, iPad, and Mac (requires iOS 17+).",
                ),

                // MARK: - Model Ecosystem (模型生态)

                .init(
                    icon: UIImage(systemName: "cpu.fill")!,
                    title: "Local Intelligence",
                    detail: "Run private, offline MLX models directly on Apple Silicon.",
                ),
                .init(
                    icon: UIImage(systemName: "network")!,
                    title: "Universal Cloud",
                    detail: "Connect to any OpenAI-compatible API or custom endpoint.",
                ),
                .init(
                    icon: UIImage(systemName: "sparkles")!,
                    title: "Apple Intelligence",
                    detail: "Native support for Apple's foundation models and ecosystem.",
                ),
                .init(
                    icon: UIImage(systemName: "gift.fill")!,
                    title: "Ready to Use",
                    detail: "Start chatting instantly with complimentary Pollinations AI models.",
                ),

                // MARK: - Powerful Capabilities (强大能力)

                .init(
                    icon: UIImage(systemName: "globe")!,
                    title: "Web Search",
                    detail: "Live internet access with citations, scraping, and verification.",
                ),
                .init(
                    icon: UIImage(systemName: "eye.fill")!,
                    title: "Visual Understanding",
                    detail: "Analyze images, screenshots, and diagrams with OCR support.",
                ),
                .init(
                    icon: UIImage(systemName: "waveform")!,
                    title: "Audio Processing",
                    detail: "Transcribe voice notes and process audio attachments.",
                ),
                .init(
                    icon: UIImage(systemName: "paperclip")!,
                    title: "Smart Attachments",
                    detail: "Summarize PDFs and text files locally before sending.",
                ),

                // MARK: - Tools & Automation (工具与自动化)

                .init(
                    icon: UIImage(systemName: "calendar")!,
                    title: "Calendar Tools",
                    detail: "Plan schedules and manage events directly within the chat.",
                ),
                .init(
                    icon: UIImage(systemName: "server.rack")!,
                    title: "MCP Integration",
                    detail: "Expand capabilities with Model Context Protocol servers.",
                ),
                .init(
                    icon: UIImage(systemName: "arrow.triangle.branch")!, // Shortcuts symbol
                    title: "Apple Shortcuts",
                    detail: "Automate workflows and Siri intents deeply integrated with OS.",
                ),

                // MARK: - Advanced Features (极客功能)

                .init(
                    icon: UIImage(systemName: "brain.head.profile")!,
                    title: "Reasoning Mode",
                    detail: "Control chain-of-thought budgets for complex problem solving.",
                ),
                .init(
                    icon: UIImage(systemName: "doc.on.doc.fill")!,
                    title: "Chat Templates",
                    detail: "Create and reuse custom personas and system prompts.",
                ),
                .init(
                    icon: UIImage(systemName: "chevron.left.forwardslash.chevron.right")!,
                    title: "Open Source",
                    detail: "Transparent architecture. Verify the code, trust the process.",
                ),
            ],
        )
    }
}
