import Foundation
import UIKit

final class DisposableExporter: NSObject {
    enum RunMode {
        case file
        case text
    }

    @MainActor
    private static var activeExporters: [UUID: DisposableExporter] = [:]

    private let identifier = UUID()
    private let deletableItem: URL
    private let title: String?

    init(
        deletableItem: URL,
        title: String.LocalizationValue? = nil,
    ) {
        self.deletableItem = deletableItem
        self.title = title.map { String(localized: $0) }
        super.init()
    }

    convenience init(
        data: Data,
        name: String = UUID().uuidString,
        pathExtension: String,
        title: String.LocalizationValue? = nil,
    ) {
        let tempDir = disposableResourcesDir
        let tempURL = tempDir
            .appendingPathComponent(name)
            .appendingPathExtension(pathExtension)

        // Ensure parent directory exists
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? data.write(to: tempURL)

        self.init(deletableItem: tempURL, title: title)
    }

    /// Where a share sheet that ends up as a popover points.
    ///
    /// Anchor to the control that started the export. A popover pointing at
    /// a whole screen lands wherever that screen's edge is, which on a large
    /// or folding display can be far from the control or across the fold.
    private enum Anchor {
        case view(UIView)
        case barButtonItem(UIBarButtonItem, presenter: UIViewController)

        @MainActor
        var presenter: UIViewController? {
            switch self {
            case let .view(view): view.parentViewController
            case let .barButtonItem(_, presenter): presenter
            }
        }
    }

    func run(anchor toView: UIView, mode: RunMode = .file) {
        Task { @MainActor in
            self.runMainActor(anchor: .view(toView), mode: mode)
        }
    }

    func run(
        anchor barButtonItem: UIBarButtonItem,
        presenter: UIViewController,
        mode: RunMode = .file,
    ) {
        Task { @MainActor in
            self.runMainActor(anchor: .barButtonItem(barButtonItem, presenter: presenter), mode: mode)
        }
    }

    @MainActor
    private func runMainActor(anchor: Anchor, mode: RunMode = .file) {
        guard let presentingViewController = anchor.presenter else {
            cleanup()
            return
        }

        retainSelf()

        #if targetEnvironment(macCatalyst)
            // Catalyst exports files through the document picker; text still
            // goes through the share sheet.
            if mode == .file {
                let picker = UIDocumentPickerViewController(forExporting: [deletableItem])
                picker.delegate = self
                if let title { picker.title = title }
                presentingViewController.present(picker, animated: true, completion: nil)
                return
            }
        #endif

        presentActivityController(anchor: anchor, from: presentingViewController)
    }

    @MainActor
    private func presentActivityController(anchor: Anchor, from presenter: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [deletableItem], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            self.cleanup()
        }
        if let popover = activityVC.popoverPresentationController {
            switch anchor {
            case let .view(toView):
                popover.sourceView = toView
                popover.sourceRect = toView.bounds
            case let .barButtonItem(item, _):
                popover.sourceItem = item
            }
        }
        presenter.present(activityVC, animated: true, completion: nil)
    }

    @MainActor
    private func retainSelf() {
        Self.activeExporters[identifier] = self
    }

    @MainActor
    private func cleanup() {
        try? FileManager.default.removeItem(at: deletableItem)
        Self.activeExporters.removeValue(forKey: identifier)
    }
}

extension DisposableExporter: UIDocumentPickerDelegate {
    // MARK: - UIDocumentPickerDelegate

    #if targetEnvironment(macCatalyst)
        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt _: [URL]) {
            cleanup()
        }

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            cleanup()
        }
    #endif
}
