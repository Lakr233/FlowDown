import AlertController
import FlowDownModelExchange
import Storage
import UIKit

final class ModelExchangeCoordinator {
    static let shared = ModelExchangeCoordinator()

    struct Context {
        let publicKey: ModelExchangePublicKey
        let callbackScheme: String
        let createdAt: Date
    }

    private var contexts: [String: Context] = [:]
    private let timeout: TimeInterval = 300
    weak var presenter: UIViewController?

    private var presentationRoot: UIViewController? {
        presenter ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
    }

    func registerPresenter(_ presenter: UIViewController) {
        self.presenter = presenter
    }

    func resolve(url: URL) -> Bool? {
        guard let stage = ModelExchangeURL.resolve(url) else { return nil }
        switch stage {
        case let .handshake(payload):
            return handleHandshake(payload)
        case let .exchange(payload):
            return handleExchange(payload, originalURL: url)
        case let .cancelled(session):
            if let session { contexts.removeValue(forKey: session) }
            return true
        }
    }

    private func handleHandshake(_ payload: ModelExchangeURL.Handshake) -> Bool {
        guard let publicKey = ModelExchangePublicKey(encoded: payload.publicKey) else { return false }
        let session = "\(Storage.deviceId)-\(UUID().uuidString)"
        contexts[session] = Context(publicKey: publicKey, callbackScheme: payload.callbackScheme, createdAt: .init())
        sendVerification(
            session: session,
            publicKey: payload.publicKey,
            callbackScheme: payload.callbackScheme,
        )
        return true
    }

    private func handleExchange(_ payload: ModelExchangeURL.Exchange, originalURL: URL) -> Bool {
        guard let context = contexts[payload.session],
              let signingKey = context.publicKey.signingKey
        else { return false }

        guard abs(payload.timestamp.timeIntervalSinceNow) < timeout else { return false }
        guard let signature = payload.signature else { return false }

        guard let canonical = canonicalPathWithoutSignature(from: originalURL),
              ModelExchangeAPI.verify(path: canonical, signature: signature, publicKey: signingKey)
        else { return false }

        presentSelector(for: payload, context: context)
        return true
    }

    private func canonicalPathWithoutSignature(from url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = components.queryItems?.filter { $0.name.lowercased() != "sig" }
        guard let url = components.url else { return nil }
        return ModelExchangeAPI.canonicalPath(from: url)
    }

    /// Builds the `<scheme>://models/exchange` callback the requesting app listens on.
    private static func callbackURL(
        scheme: String,
        stage: String,
        session: String,
        extraItems: [URLQueryItem] = [],
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "models"
        components.path = "/exchange"
        components.queryItems = [
            .init(name: "stage", value: stage),
            .init(name: "session", value: session),
        ] + extraItems
        return components.url
    }

    private func sendVerification(session: String, publicKey: String, callbackScheme: String) {
        guard let url = Self.callbackURL(
            scheme: callbackScheme,
            stage: "verification",
            session: session,
            extraItems: [.init(name: "pk", value: publicKey)],
        ) else { return }
        Task { @MainActor in
            UIApplication.shared.open(url)
        }
    }

    private func presentSelector(for payload: ModelExchangeURL.Exchange, context: Context) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let presented = ModelExchangeSelectionController.makePresentedController(
                appName: payload.appName,
                reason: payload.reason,
                capabilities: payload.capabilities,
                multipleSelection: payload.multipleSelection,
                onCancel: { [weak self] in
                    self?.sendCancel(session: payload.session, callbackScheme: context.callbackScheme)
                    self?.contexts.removeValue(forKey: payload.session)
                },
                onConfirm: { [weak self] models in
                    self?.deliver(models: models, payload: payload, context: context)
                },
            )

            presentationRoot?.topMostController.present(presented, animated: true)
        }
    }

    private func deliver(models: [CloudModel], payload: ModelExchangeURL.Exchange, context: Context) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .xml
                let data = try encoder.encode(models)
                let sealed = try ModelExchangeCrypto.encrypt(data, for: context.publicKey, session: payload.session)
                let encodedPayload = try sealed.encoded()

                guard let url = Self.callbackURL(
                    scheme: context.callbackScheme,
                    stage: "completed",
                    session: payload.session,
                    extraItems: [
                        .init(name: "format", value: "plist"),
                        .init(name: "payload", value: encodedPayload),
                    ],
                ) else { return }
                UIApplication.shared.open(url)
            } catch {
                guard let target = presentationRoot else { return }
                let alert = AlertViewController(
                    title: "Share Failed",
                    message: "Model encryption or delivery failed: \(error.localizedDescription)",
                ) { context in
                    context.allowSimpleDispose()
                    context.addAction(title: "OK") {
                        context.dispose {}
                    }
                }
                target.present(alert, animated: true)
            }
            contexts.removeValue(forKey: payload.session)
        }
    }

    private func sendCancel(session: String, callbackScheme: String) {
        guard let url = Self.callbackURL(
            scheme: callbackScheme,
            stage: "cancelled",
            session: session,
        ) else { return }
        UIApplication.shared.open(url)
    }
}

public extension ModelExchangeAPI {
    static func resolveInputScheme(_ url: URL) -> Bool? {
        ModelExchangeCoordinator.shared.resolve(url: url)
    }
}
