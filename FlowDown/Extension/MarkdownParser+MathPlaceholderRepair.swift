//
//  MarkdownParser+MathPlaceholderRepair.swift
//  FlowDown
//
//  Created by Codex on 2026/2/22.
//

import MarkdownParser
import MarkdownView

extension MarkdownContent {
    /// One-step content build that routes blocks through the inline-math
    /// placeholder repair. Mirror of MarkdownContent(parserResult:theme:);
    /// delete this once upstream repairs placeholders itself.
    @MainActor
    convenience init(repairing result: MarkdownParser.ParseResult, theme: MarkdownTheme) {
        self.init(
            blocks: result.documentByRepairingInlineMathPlaceholders(),
            rendered: result.renderedContent(theme: theme),
            highlightMaps: result.highlightMaps(theme: theme),
        )
    }
}

extension MarkdownParser.ParseResult {
    func documentByRepairingInlineMathPlaceholders() -> [MarkdownBlockNode] {
        document.map { repair(block: $0) }
    }

    private func repair(block: MarkdownBlockNode) -> MarkdownBlockNode {
        switch block {
        case let .blockquote(children):
            return .blockquote(children: children.map { repair(block: $0) })
        case let .bulletedList(isTight, items):
            let repairedItems = items.map { item in
                RawListItem(children: item.children.map { repair(block: $0) })
            }
            return .bulletedList(isTight: isTight, items: repairedItems)
        case let .numberedList(isTight, start, items):
            let repairedItems = items.map { item in
                RawListItem(children: item.children.map { repair(block: $0) })
            }
            return .numberedList(isTight: isTight, start: start, items: repairedItems)
        case let .taskList(isTight, items):
            let repairedItems = items.map { item in
                RawTaskListItem(
                    isCompleted: item.isCompleted,
                    children: item.children.map { repair(block: $0) },
                )
            }
            return .taskList(isTight: isTight, items: repairedItems)
        case let .paragraph(content):
            return .paragraph(content: repairInlineNodes(content))
        case let .heading(level, content):
            return .heading(level: level, content: repairInlineNodes(content))
        case let .table(columnAlignments, rows):
            let repairedRows = rows.map { row in
                let repairedCells = row.cells.map { cell in
                    RawTableCell(content: repairInlineNodes(cell.content))
                }
                return RawTableRow(cells: repairedCells)
            }
            return .table(columnAlignments: columnAlignments, rows: repairedRows)
        case .codeBlock, .thematicBreak:
            return block
        }
    }

    private func repairInlineNodes(_ nodes: [MarkdownInlineNode]) -> [MarkdownInlineNode] {
        nodes.map { repair(inlineNode: $0) }
    }

    private func repair(inlineNode: MarkdownInlineNode) -> MarkdownInlineNode {
        switch inlineNode {
        case let .code(content):
            mathNodeFromReplacementCode(content) ?? inlineNode
        case let .emphasis(children):
            .emphasis(children: repairInlineNodes(children))
        case let .strong(children):
            .strong(children: repairInlineNodes(children))
        case let .strikethrough(children):
            .strikethrough(children: repairInlineNodes(children))
        case let .link(destination, children):
            .link(destination: destination, children: repairInlineNodes(children))
        case let .image(source, children):
            .image(source: source, children: repairInlineNodes(children))
        default:
            inlineNode
        }
    }

    private func mathNodeFromReplacementCode(_ content: String) -> MarkdownInlineNode? {
        guard MarkdownParser.typeForReplacementText(content) == .math else { return nil }
        guard let identifier = MarkdownParser.identifierForReplacementText(content),
              let index = Int(identifier),
              let latex = mathContext[index]
        else {
            return nil
        }
        return .math(
            content: latex,
            replacementIdentifier: MarkdownParser.replacementText(
                for: .math,
                identifier: identifier,
            ),
        )
    }
}
