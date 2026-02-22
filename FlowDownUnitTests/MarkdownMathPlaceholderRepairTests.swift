@testable import FlowDown
import MarkdownParser
import Testing

@Suite
final class MarkdownMathPlaceholderRepairTests {
    @Test("Repair keeps math placeholders from leaking inside strong text")
    func repairStrongInlineMathPlaceholder() {
        let markdown = "**Conclusion: for points outside a uniform thin spherical shell, gravity is equivalent to placing total shell mass \\\\(M_s\\\\) at the center.**"
        let result = MarkdownParser().parse(markdown)

        #expect(containsMathPlaceholderCode(in: result.document))

        let repaired = result.documentByRepairingInlineMathPlaceholders()
        #expect(!containsMathPlaceholderCode(in: repaired))
        #expect(containsMathNode(in: repaired))
    }

    @Test("Repair handles nested inline containers")
    func repairNestedInlineMathPlaceholder() {
        let markdown = "_See **\\(a^2+b^2=c^2\\)** for the proof._"
        let result = MarkdownParser().parse(markdown)

        #expect(containsMathPlaceholderCode(in: result.document))

        let repaired = result.documentByRepairingInlineMathPlaceholders()
        #expect(!containsMathPlaceholderCode(in: repaired))
        #expect(containsMathNode(in: repaired))
    }
}

private func containsMathPlaceholderCode(in blocks: [MarkdownBlockNode]) -> Bool {
    blocks.contains { block in
        switch block {
        case let .blockquote(children):
            return containsMathPlaceholderCode(in: children)
        case let .bulletedList(_, items):
            return items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .numberedList(_, _, items):
            return items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .taskList(_, items):
            return items.contains { containsMathPlaceholderCode(in: $0.children) }
        case let .paragraph(content), let .heading(_, content):
            return containsMathPlaceholderCode(in: content)
        case let .table(_, rows):
            return rows.contains { row in
                row.cells.contains { containsMathPlaceholderCode(in: $0.content) }
            }
        case .codeBlock, .thematicBreak:
            return false
        }
    }
}

private func containsMathPlaceholderCode(in nodes: [MarkdownInlineNode]) -> Bool {
    nodes.contains { node in
        switch node {
        case let .code(content):
            return MarkdownParser.typeForReplacementText(content) == .math
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            return containsMathPlaceholderCode(in: children)
        case let .link(_, children), let .image(_, children):
            return containsMathPlaceholderCode(in: children)
        default:
            return false
        }
    }
}

private func containsMathNode(in blocks: [MarkdownBlockNode]) -> Bool {
    blocks.contains { block in
        switch block {
        case let .blockquote(children):
            return containsMathNode(in: children)
        case let .bulletedList(_, items):
            return items.contains { containsMathNode(in: $0.children) }
        case let .numberedList(_, _, items):
            return items.contains { containsMathNode(in: $0.children) }
        case let .taskList(_, items):
            return items.contains { containsMathNode(in: $0.children) }
        case let .paragraph(content), let .heading(_, content):
            return containsMathNode(in: content)
        case let .table(_, rows):
            return rows.contains { row in
                row.cells.contains { containsMathNode(in: $0.content) }
            }
        case .codeBlock, .thematicBreak:
            return false
        }
    }
}

private func containsMathNode(in nodes: [MarkdownInlineNode]) -> Bool {
    nodes.contains { node in
        switch node {
        case .math(_, _):
            return true
        case let .emphasis(children), let .strong(children), let .strikethrough(children):
            return containsMathNode(in: children)
        case let .link(_, children), let .image(_, children):
            return containsMathNode(in: children)
        default:
            return false
        }
    }
}
