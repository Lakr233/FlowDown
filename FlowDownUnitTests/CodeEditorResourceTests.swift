//
//  CodeEditorResourceTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import RunestoneEditor
import Testing
import UIKit

/// Runestone.xcframework is a static framework: its code links into FlowDown,
/// and Xcode embeds Runestone.framework only for its resources. Runestone
/// force-unwraps its theme colors and Tree-sitter query files from that
/// bundle, so a build that stops embedding it crashes the code editor on open.
/// Every test first requires the embedded resources, so a missing embed fails
/// here instead of taking the test host down.
@MainActor
struct CodeEditorResourceTests {
    @Test
    func runestoneFramework_isEmbeddedWithResources() throws {
        try requireRunestoneResources()
    }

    @Test
    func tomorrowTheme_loadsColorsFromRunestoneBundle() throws {
        try requireRunestoneResources()

        let theme = TomorrowTheme()

        #expect(theme.textColor(for: "string") != nil)
    }

    @Test(arguments: ["json", "markdown", "swift", "python"])
    func treeSitterLanguage_loadsHighlightsQuery(identifier: String) throws {
        try requireRunestoneResources()

        let language = try #require(TreeSitterLanguage.language(withIdentifier: identifier))

        #expect(language.highlightsQuery != nil)
    }

    @Test
    func jsonSyntaxHighlight_colorsTokensWithTomorrowTheme() throws {
        try requireRunestoneResources()

        let highlighter = StringSyntaxHighlighter(theme: TomorrowTheme(), language: .json)
        let highlighted = highlighter.syntaxHighlight(#"{"key": "value", "count": 1}"#)

        var colors: Set<UIColor> = []
        highlighted.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: highlighted.length),
        ) { value, _, _ in
            if let color = value as? UIColor {
                colors.insert(color)
            }
        }
        #expect(colors.count > 1)
    }

    @Test
    func jsonEditorController_opensWithThemeAndLanguage() throws {
        try requireRunestoneResources()

        let text = #"{"key": 1}"#
        let controller = JsonEditorController(text: text)
        controller.loadViewIfNeeded()

        #expect(controller.textView.text == text)
    }

    private func requireRunestoneResources() throws {
        let frameworks = try #require(Bundle.main.privateFrameworksURL)
        let url = frameworks.appendingPathComponent("Runestone.framework")
        let bundle = try #require(
            Bundle(url: url),
            "Runestone.framework is not embedded in \(frameworks.path)",
        )
        try #require(
            bundle.url(forResource: "Assets", withExtension: "car") != nil,
            "Runestone.framework has no compiled theme colors",
        )
        let files = FileManager.default.enumerator(at: bundle.bundleURL, includingPropertiesForKeys: nil)
        let hasQueries = files?.contains { ($0 as? URL)?.pathExtension == "scm" } ?? false
        try #require(hasQueries, "Runestone.framework has no Tree-sitter query files")
    }
}
