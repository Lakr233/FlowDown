//
//  MarkdownParser+MathPlaceholderRepair.swift
//  FlowDown
//
//  Created by Codex on 2026/2/22.
//

import MarkdownParser

extension MarkdownParser.ParseResult {
    func documentByRepairingInlineMathPlaceholders() -> [MarkdownBlockNode] {
        document.map { repair(block: $0, mathContext: mathContext) }
    }

    private func repair(block: MarkdownBlockNode, mathContext: [Int: String]) -> MarkdownBlockNode {
        switch block {
        case let .blockquote(children):
            return .blockquote(children: children.map { repair(block: $0, mathContext: mathContext) })
        case let .bulletedList(isTight, items):
            let repairedItems = items.map { item in
                RawListItem(children: item.children.map { repair(block: $0, mathContext: mathContext) })
            }
            return .bulletedList(isTight: isTight, items: repairedItems)
        case let .numberedList(isTight, start, items):
            let repairedItems = items.map { item in
                RawListItem(children: item.children.map { repair(block: $0, mathContext: mathContext) })
            }
            return .numberedList(isTight: isTight, start: start, items: repairedItems)
        case let .taskList(isTight, items):
            let repairedItems = items.map { item in
                RawTaskListItem(
                    isCompleted: item.isCompleted,
                    children: item.children.map { repair(block: $0, mathContext: mathContext) }
                )
            }
            return .taskList(isTight: isTight, items: repairedItems)
        case let .paragraph(content):
            return .paragraph(content: repairInlineNodes(content, mathContext: mathContext))
        case let .heading(level, content):
            return .heading(level: level, content: repairInlineNodes(content, mathContext: mathContext))
        case let .table(columnAlignments, rows):
            let repairedRows = rows.map { row in
                let repairedCells = row.cells.map { cell in
                    RawTableCell(content: repairInlineNodes(cell.content, mathContext: mathContext))
                }
                return RawTableRow(cells: repairedCells)
            }
            return .table(columnAlignments: columnAlignments, rows: repairedRows)
        case .codeBlock, .thematicBreak:
            return block
        }
    }

    private func repairInlineNodes(_ nodes: [MarkdownInlineNode], mathContext: [Int: String]) -> [MarkdownInlineNode] {
        nodes.map { repair(inlineNode: $0, mathContext: mathContext) }
    }

    private func repair(inlineNode: MarkdownInlineNode, mathContext: [Int: String]) -> MarkdownInlineNode {
        switch inlineNode {
        case let .code(content):
            return mathNodeFromReplacementCode(content, mathContext: mathContext) ?? inlineNode
        case let .emphasis(children):
            return .emphasis(children: repairInlineNodes(children, mathContext: mathContext))
        case let .strong(children):
            return .strong(children: repairInlineNodes(children, mathContext: mathContext))
        case let .strikethrough(children):
            return .strikethrough(children: repairInlineNodes(children, mathContext: mathContext))
        case let .link(destination, children):
            return .link(destination: destination, children: repairInlineNodes(children, mathContext: mathContext))
        case let .image(source, children):
            return .image(source: source, children: repairInlineNodes(children, mathContext: mathContext))
        default:
            return inlineNode
        }
    }

    private func mathNodeFromReplacementCode(_ content: String, mathContext: [Int: String]) -> MarkdownInlineNode? {
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
                identifier: identifier
            )
        )
    }
}
