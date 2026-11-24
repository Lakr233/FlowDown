//
//  ToolsController+MCPServerCell.swift
//  FlowDown
//
//  Created by LiBr on 6/30/25.
//

import ConfigurableKit
import Storage
import UIKit

extension SettingController.SettingContent.ToolsController {
    class MCPServerCell: UITableViewCell {
        private var timer: Timer?

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            let margin = AutoLayoutMarginView(configurableView)
            contentView.addSubview(margin)
            // Drawn by the row itself so it slides with the row when swiped,
            // matching the separators the rest of the page stacks between rows.
            let separator = SeparatorView()
            contentView.addSubview(separator)
            margin.snp.makeConstraints { make in
                make.top.leading.trailing.equalToSuperview()
            }
            separator.snp.makeConstraints { make in
                make.top.equalTo(margin.snp.bottom)
                make.leading.trailing.bottom.equalToSuperview()
                make.height.equalTo(1)
            }
            separatorInset = .zero
            selectionStyle = .none
            backgroundColor = .clear
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard let clientId else { return }
                configure(with: clientId) // update the status
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        deinit {
            timer?.invalidate()
        }

        let configurableView = ConfigurableActionView(
            responseEverywhere: true,
            actionBlock: { _ in },
        )

        var clientId: ModelContextServer.ID?

        override func prepareForReuse() {
            super.prepareForReuse()
            clientId = nil
        }

        func configure(with clientId: ModelContextServer.ID) {
            self.clientId = clientId
            guard let client = MCPService.shared.server(with: clientId) else {
                return
            }

            let icon = switch client.type {
            case .http:
                UIImage(systemName: "network") ?? UIImage()
            }

            configurableView.configure(icon: icon)
            configurableView.configure(title: "\(client.displayName)")

            var descriptions: [String] = []
            descriptions.append(client.type.rawValue.uppercased())

            let authorization = MCPService.shared.authorizationState(for: clientId)
            if client.isEnabled, client.connectionStatus != .connected, authorization.needsSignIn {
                descriptions.append(String(localized: "Sign-In Required"))
                configurableView.iconView.tintColor = .systemOrange
            } else if client.isEnabled, client.connectionStatus != .connected, case .unsupported = authorization {
                descriptions.append(String(localized: "Authorization Required"))
                configurableView.iconView.tintColor = .systemRed
            } else if client.isEnabled {
                let connectionStatusText = getConnectionStatusText(client.connectionStatus)
                descriptions.append(connectionStatusText)

                configurableView.iconView.tintColor = getConnectionStatusColor(client.connectionStatus)
            } else {
                descriptions.append(String(localized: "Disabled"))
                configurableView.iconView.tintColor = .systemGray
            }

            // Transport on the first line, status on its own line below.
            let desc = descriptions.joined(separator: "\n")
            configurableView.configure(description: "\(desc)")
        }

        private func getConnectionStatusText(_ status: ModelContextServer.ConnectionStatus) -> String {
            switch status {
            case .connected:
                String(localized: "Connected")
            case .connecting:
                String(localized: "Connecting...")
            case .disconnected:
                String(localized: "Disconnected")
            case .failed:
                String(localized: "Connection Failed")
            }
        }

        private func getConnectionStatusColor(_ status: ModelContextServer.ConnectionStatus) -> UIColor {
            switch status {
            case .connected:
                UIColor(red: 65 / 255.0, green: 190 / 255.0, blue: 171 / 255.0, alpha: 1.0)
            case .connecting:
                .systemOrange
            case .disconnected:
                .systemGray
            case .failed:
                .systemRed
            }
        }
    }
}
