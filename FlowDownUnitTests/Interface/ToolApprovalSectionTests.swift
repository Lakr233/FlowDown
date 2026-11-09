//
//  ToolApprovalSectionTests.swift
//  FlowDownUnitTests
//

import Combine
@testable import FlowDown
import Foundation
import Testing
import UIKit

@Suite(.serialized)
struct ToolApprovalSectionTests {
    @MainActor
    @Test
    func `a waiting call covers the input and the input returns once it is answered`() {
        let host = EditorHost()
        let inputHeight = host.editor.heightPublisher.value

        host.editor.showToolApproval(Self.request)
        host.layout()

        #expect(host.editor.toolApproval.isPresenting)
        #expect(host.editor.inputEditor.alpha == 0)
        #expect(host.editor.quickSettingBar.alpha == 0)
        #expect(!host.editor.inputEditor.isUserInteractionEnabled)
        #expect(host.editor.toolApproval.frame.height > 0)
        #expect(host.editor.heightPublisher.value == host.editor.toolApproval.frame.maxY + host.editor.spacing)

        host.editor.showToolApproval(nil)
        host.layout()

        #expect(!host.editor.toolApproval.isPresenting)
        #expect(host.editor.inputEditor.alpha == 1)
        #expect(host.editor.inputEditor.isUserInteractionEnabled)
        #expect(host.editor.heightPublisher.value == inputHeight)
    }

    @MainActor
    @Test
    func `the card reports the decision for the request it shows`() {
        let host = EditorHost()
        var decisions: [(UUID, ModelToolApprovalDecision)] = []
        host.editor.toolApproval.onDecision = { request, decision in
            decisions.append((request.id, decision))
        }
        host.editor.showToolApproval(Self.request)
        host.layout()

        let buttons = host.editor.toolApproval.subviews.compactMap { $0 as? UIButton }
        let allow = buttons.first { $0.title(for: .normal) == String(localized: "Allow") }
        allow?.sendActions(for: .touchUpInside)

        #expect(decisions.count == 1)
        #expect(decisions.first?.0 == Self.request.id)
        #expect(decisions.first?.1 == .approve)
    }

    static let request = ModelToolApprovalRequest(
        id: UUID(),
        toolName: "Add to Calendar",
        icon: "calendar",
        source: nil,
        reason: "Save the dentist appointment you mentioned",
        summary: "Event: Dentist\n\nStart: Nov 9, 2026 at 10:00 AM\nEnd: Nov 9, 2026 at 11:00 AM",
        arguments: "{}",
    )
}

/// A window holding the editor at a phone's width, pinned to the bottom the
/// way ChatView pins it.
@MainActor
final class EditorHost {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    let editor = RichEditorView()

    init() {
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(editor)
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -34),
        ])
        layout()
    }

    func layout() {
        for _ in 0 ..< 3 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            editor.setNeedsLayout()
            editor.layoutIfNeeded()
        }
    }
}
