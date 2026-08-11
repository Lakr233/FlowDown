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

    func run(anchor toView: UIView, mode: RunMode = .file) {
        Task { @MainActor in
            self.runMainActor(anchor: toView, mode: mode)
        }
    }

    @MainActor
    private func runMainActor(anchor toView: UIView, mode: RunMode = .file) {
        guard let presentingViewController = toView.parentViewController else {
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

        presentActivityController(anchor: toView, from: presentingViewController)
    }

    @MainActor
    private func presentActivityController(anchor toView: UIView, from presenter: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [deletableItem], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            self.cleanup()
        }
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = toView
            popover.sourceRect = toView.bounds
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
