@testable import FlowDown
import MarkdownParser
import Testing

final class MarkdownMathPlaceholderRepairTests {
    @Test
    func `Repair keeps math placeholders from leaking inside strong text`() {
        let markdown = "**Conclusion: for points outside a uniform thin spherical shell, gravity is equivalent to placing total shell mass \\\\(M_s\\\\) at the center.**"
        let result = MarkdownParser().parse(markdown)

        #expect(
            containsMathPlaceholderCode(in: result.document)
                || containsMathNode(in: result.document),
        )

        let repaired = result.documentByRepairingInlineMathPlaceholders()
        #expect(!containsMathPlaceholderCode(in: repaired))
        #expect(containsMathNode(in: repaired))
    }

    @Test
    func `Repair handles nested inline containers`() {
        let markdown = "_See **\\(a^2+b^2=c^2\\)** for the proof._"
        let result = MarkdownParser().parse(markdown)

        #expect(
            containsMathPlaceholderCode(in: result.document)
                || containsMathNode(in: result.document),
        )

        let repaired = result.documentByRepairingInlineMathPlaceholders()
        #expect(!containsMathPlaceholderCode(in: repaired))
        #expect(containsMathNode(in: repaired))
    }
}

private func containsMathPlaceholderCode(in blocks: [MarkdownBlockNode]) -> Bool {
    blocks.contains { block in
        switch block {
        case let .blockquote(children):
            containsMathPlaceholderCode(in: children)
        case let .bulletedList(_, items):
            items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .numberedList(_, _, items):
            items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .taskList(_, items):
            items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .paragraph(content), let .heading(_, content):
            containsMathPlaceholderCode(in: content)
        case let .table(_, rows):
            rows.contains { row in
                row.cells.contains { containsMathPlaceholderCode(in: $0.content) }
            }
        case .codeBlock, .thematicBreak:
            false
        }
    }
}

private func containsMathPlaceholderCode(in nodes: [MarkdownInlineNode]) -> Bool {
    nodes.contains { node in
        switch node {
        case let .code(content):
            MarkdownParser.typeForReplacementText(content) == .math
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            containsMathPlaceholderCode(in: children)
        case let .link(_, children), let .image(_, children):
            containsMathPlaceholderCode(in: children)
        default:
            false
        }
    }
}

private func containsMathNode(in blocks: [MarkdownBlockNode]) -> Bool {
    blocks.contains { block in
        switch block {
        case let .blockquote(children):
            containsMathNode(in: children)
        case let .bulletedList(_, items):
            items.contains { containsMathNode(in: $0.children) }
        case let .numberedList(_, _, items):
            items.contains { containsMathNode(in: $0.children) }
        case let .taskList(_, items):
            items.contains { containsMathNode(in: $0.children) }
        case let .paragraph(content), let .heading(_, content):
            containsMathNode(in: content)
        case let .table(_, rows):
            rows.contains { row in
                row.cells.contains { containsMathNode(in: $0.content) }
            }
        case .codeBlock, .thematicBreak:
            false
        }
    }
}

private func containsMathNode(in nodes: [MarkdownInlineNode]) -> Bool {
    nodes.contains { node in
        switch node {
        case .math:
            true
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            containsMathNode(in: children)
        case let .link(_, children), let .image(_, children):
            containsMathNode(in: children)
        default:
            false
        }
    }
}
