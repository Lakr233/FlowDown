import AlertController
import Combine
import ConfigurableKit
import MCP
import Storage
import UIKit

class MCPEditorController: StackScrollController {
    let serverId: ModelContextServer.ID
    var cancellables: Set<AnyCancellable> = .init()

    init(clientId: ModelContextServer.ID) {
        serverId = clientId
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Edit MCP Server")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    let testFooterView = ConfigurableSectionFooterView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background

        navigationItem.rightBarButtonItem = .init(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(checkTapped),
        )

        MCPService.shared.servers
            .removeDuplicates()
            .ensureMainThread()
            .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] clients in
                guard let self, isVisible else { return }
                if !clients.contains(where: { $0.id == self.serverId }) {
                    navigationController?.popViewController(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshUI()
    }

    @objc func checkTapped() {
        navigationController?.popViewController(animated: true)
        MCPService.shared.ensureOrReconnect(serverId)
    }

    @objc func exportTapped() {
        guard let server = MCPService.shared.server(with: serverId) else { return }

        let serverName = if let url = URL(string: server.endpoint), let host = url.host {
            host
        } else if !server.name.isEmpty {
            server.name
        } else {
            "MCPServer"
        }

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(server)
            let fileName = "Export-\(serverName.sanitizedFileName)"

            DisposableExporter(
                data: data,
                name: fileName,
                pathExtension: "fdmcp",
                title: "Export MCP Server",
            ).run(anchor: view)
        } catch {
            Logger.app.errorFile("failed to export MCP server: \(error)")
        }
    }

    @objc func deleteTapped() {
        presentDeleteConfirmation(
            title: "Delete Server",
            message: "Are you sure you want to delete this MCP server? This action cannot be undone.",
        ) { [weak self] in
            guard let self else { return }
            MCPService.shared.remove(serverId)
            navigationController?.popViewController(animated: true)
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        guard let server = MCPService.shared.server(with: serverId) else { return }

        if !server.comment.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView()
                    .with(header: "Comment"),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView()
                    .with(rawFooter: server.comment),
            )
        }

        // MARK: - Enabled

        stackView.addArrangedSubview(SeparatorView())
        let enabledView = ConfigurableToggleActionView()
        enabledView.boolValue = server.isEnabled
        enabledView.actionBlock = { value in
            MCPService.shared.edit(identifier: self.serverId) {
                $0.update(\.isEnabled, to: value)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                // let toggle finish animate
                self.refreshUI()
            }
        }
        enabledView.configure(icon: .init(systemName: "power"))
        enabledView.configure(title: "Enabled")
        enabledView.configure(description: "Determine if this MCP server is enabled. Tools are only updated when this server is enabled.")
        stackView.addArrangedSubviewWithMargin(enabledView)
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Connection

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Connection"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let typeView = ConfigurableInfoView()
        typeView.configure(icon: .init(systemName: "gear"))
        typeView.configure(title: "Connection Type")
        typeView.configure(description: "The transport protocol to use for this client.")
        typeView.configure(value: server.type.rawValue.uppercased())
        typeView.use {
            [
                UIAction(
                    title: String(localized: "Streamable HTTP"),
                    image: UIImage(systemName: "network"),
                ) { _ in
                    MCPService.shared.edit(identifier: self.serverId) {
                        $0.update(\.type, to: .http)
                    }
                    self.refreshUI()
                    typeView.configure(value: String(localized: "Streamable HTTP"))
                },
            ]
        }
        stackView.addArrangedSubviewWithMargin(typeView)
        stackView.addArrangedSubview(SeparatorView())

        let endpointView = ConfigurableInfoView().setTapBlock { view in
            let input = AlertInputViewController(
                title: "Edit Endpoint",
                message: "The URL endpoint for this MCP server. Most of them requires /mcp/ suffix.",
                placeholder: "\("https://")",
                text: server.endpoint.isEmpty ? "https://" : server.endpoint,
            ) { output in
                MCPService.shared.edit(identifier: self.serverId) {
                    $0.update(\.endpoint, to: output)
                }
                self.refreshUI()
                view.configure(value: output.isEmpty ? "Not Configured" : output)
            }
            view.parentViewController?.present(input, animated: true)
        }
        endpointView.configure(icon: .init(systemName: "link"))
        endpointView.configure(title: "Endpoint")
        endpointView.configure(description: "The URL endpoint for this MCP server. Most of them requires /mcp/ suffix.")
        endpointView.configure(value: server.endpoint.isEmpty ? "Not Configured" : server.endpoint)
        stackView.addArrangedSubviewWithMargin(endpointView)
        stackView.addArrangedSubview(SeparatorView())

        let headerView = ConfigurableInfoView().setTapBlock { view in
            guard let client = MCPService.shared.server(with: self.serverId) else { return }
            var text = client.header
            if text.isEmpty { text = "{}" }
            let textEditor = JsonStringMapEditorController(text: text)
            textEditor.title = String(localized: "Edit Headers")
            textEditor.collectEditedContent { result in
                guard let object = try? JSONDecoder().decode([String: String].self, from: result.data(using: .utf8) ?? .init()) else {
                    return
                }
                let jsonData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
                let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? ""
                MCPService.shared.edit(identifier: self.serverId) {
                    let header = jsonString == "{}" ? "" : jsonString
                    $0.update(\.header, to: header)
                }
                self.refreshUI()
                view.configure(value: object.isEmpty ? String(localized: "No Headers") : String(localized: "Configured"))
            }
            view.parentViewController?.navigationController?.pushViewController(textEditor, animated: true)
        }
        headerView.configure(icon: .init(systemName: "list.bullet"))
        headerView.configure(title: "Headers")
        headerView.configure(description: "This value will be added to the request as additional header.")
        headerView.configure(value: server.header.isEmpty ? String(localized: "No Headers") : String(localized: "Configured"))
        stackView.addArrangedSubviewWithMargin(headerView)
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Customization

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Customization"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let nicknameView = ConfigurableInfoView().setTapBlock { view in
            guard let client = MCPService.shared.server(with: self.serverId) else { return }
            let input = AlertInputViewController(
                title: "Edit Nickname",
                message: "Custom display name for this MCP server.",
                placeholder: "Nickname (Optional)",
                text: client.name,
            ) { output in
                MCPService.shared.edit(identifier: self.serverId) {
                    $0.update(\.name, to: output)
                }
                self.refreshUI()
                view.configure(value: output.isEmpty ? String(localized: "Not Configured") : output)
            }
            view.parentViewController?.present(input, animated: true)
        }
        nicknameView.configure(icon: .init(systemName: "tag"))
        nicknameView.configure(title: "Nickname")
        nicknameView.configure(description: "Custom display name for this MCP server.")
        nicknameView.configure(
            value: server.name.isEmpty ? String(localized: "Not Configured") : server.name,
        )
        stackView.addArrangedSubviewWithMargin(nicknameView)
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Test

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Verification"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let testAction = ConfigurableActionView { @MainActor [weak self] _ in
            guard let self else { return }
            testConfiguration()
        }
        testAction.configure(icon: UIImage(systemName: "testtube.2"))
        testAction.configure(title: "Verify Configuration")
        testAction.configure(description: "Verify the configuration of this MCP server and list available tools for your inform.")
        stackView.addArrangedSubviewWithMargin(testAction)
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(testFooterView) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Management

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Management"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let exportOption = ConfigurableActionView { @MainActor [weak self] _ in
            guard let self else { return }
            exportTapped()
        }
        exportOption.configure(icon: UIImage(systemName: "square.and.arrow.up"))
        exportOption.configure(title: "Export Server")
        exportOption.configure(description: "Export this MCP server as a .fdmcp file for sharing or backup.")
        stackView.addArrangedSubviewWithMargin(exportOption)
        stackView.addArrangedSubview(SeparatorView())

        let deleteAction = ConfigurableActionView { @MainActor [weak self] _ in
            guard let self else { return }
            deleteTapped()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: "Delete Server")
        deleteAction.configure(description: "Delete this MCP server permanently.")
        deleteAction.titleLabel.textColor = .systemRed
        deleteAction.iconView.tintColor = .systemRed
        deleteAction.descriptionLabel.textColor = .systemRed
        deleteAction.imageView.tintColor = .systemRed
        stackView.addArrangedSubviewWithMargin(deleteAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(UIView())

        // MARK: FOOTER

        let icon = UIImageView().with {
            $0.image = .modelCloud
            $0.tintColor = .separator
            $0.contentMode = .scaleAspectFit
            $0.snp.makeConstraints { make in
                make.width.height.equalTo(24)
            }
        }
        stackView.addArrangedSubviewWithMargin(icon) { $0.bottom /= 2 }

        let footer = UILabel().with {
            $0.font = .rounded(
                ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
                weight: .regular,
            )
            $0.textColor = .label.withAlphaComponent(0.25)
            $0.numberOfLines = 0
            $0.text = serverId
            $0.textAlignment = .center
        }
        stackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
        stackView.addArrangedSubviewWithMargin(UIView())
    }
}

extension MCPEditorController {
    func refreshUI() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        setupContentViews()
        applySeparatorConstraints()
    }

    func applySeparatorConstraints() {
        stackView
            .subviews
            .compactMap { view -> SeparatorView? in
                if view is SeparatorView {
                    return view as? SeparatorView
                }
                return nil
            }.forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    $0.heightAnchor.constraint(equalToConstant: 1),
                    $0.widthAnchor.constraint(equalTo: stackView.widthAnchor),
                ])
            }
    }

    func testConfiguration() {
        Indicator.progress(
            title: "Verifying Configuration",
            controller: self,
        ) { completionHandler in
            let result = await withCheckedContinuation { continuation in
                MCPService.shared.testConnection(
                    serverID: self.serverId,
                ) { result in
                    continuation.resume(returning: result)
                }
            }
            let tools = try result.get()
            await completionHandler {
                Indicator.present(
                    title: "Configuration Verified",
                    referencingView: self.view,
                )
                self.testFooterView.with(footer: "Available tool(s): \(tools)")
            }
        }
    }
}
