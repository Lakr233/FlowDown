import AppIntents

struct Shortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .lime }

    static var appShortcuts: [AppShortcut] {
        var shortcuts: [AppShortcut] = [
            AppShortcut(
                intent: GenerateChatResponseIntent(),
                phrases: [
                    "Ask Model on \(.applicationName)",
                ],
                shortTitle: LocalizedStringResource("Ask Model"),
                systemImageName: "text.bubble"
            ),
            AppShortcut(
                intent: SetConversationModelIntent(),
                phrases: [
                    "Set conversation model on \(.applicationName)",
                    "Set default model on \(.applicationName)",
                ],
                shortTitle: LocalizedStringResource("Set Model"),
                systemImageName: "slider.horizontal.3"
            ),
            AppShortcut(
                intent: GenerateNewConversationLinkIntent(),
                phrases: [
                    "Create FlowDown link on \(.applicationName)",
                    "New conversation link on \(.applicationName)",
                ],
                shortTitle: LocalizedStringResource("Conversation Link"),
                systemImageName: "link"
            ),
        ]

        shortcuts.append(
            AppShortcut(
                intent: ClassifyContentIntent(),
                phrases: [
                    "Classify content on \(.applicationName)",
                    "Classify with \(.applicationName)",
                ],
                shortTitle: LocalizedStringResource("Classify"),
                systemImageName: "checklist"
            )
        )

        shortcuts.append(
            AppShortcut(
                intent: SearchConversationsIntent(),
                phrases: [
                    "Search conversations on \(.applicationName)",
                    "Find chats on \(.applicationName)",
                ],
                shortTitle: LocalizedStringResource("Search Chats"),
                systemImageName: "magnifyingglass"
            )
        )

        if #available(iOS 18.0, macCatalyst 18.0, *) {
            shortcuts.append(
                AppShortcut(
                    intent: GenerateChatResponseWithImagesIntent(),
                    phrases: [
                        "Ask Model with image on \(.applicationName)",
                    ],
                    shortTitle: LocalizedStringResource("Ask Model + Image"),
                    systemImageName: "photo"
                )
            )

            shortcuts.append(
                AppShortcut(
                    intent: ClassifyContentWithImageIntent(),
                    phrases: [
                        "Classify image on \(.applicationName)",
                        "Classify content with image on \(.applicationName)",
                    ],
                    shortTitle: LocalizedStringResource("Classify + Image"),
                    systemImageName: "photo.badge.checkmark"
                )
            )
        }

        return shortcuts
    }
}
