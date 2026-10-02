//
//  RecoveryMode.swift
//  FlowDown
//
//  Created by qaq on 9/12/2025.
//

import Foundation
import SwiftUI
import UIKit

enum RecoveryMode {
    static var isActivated: Bool {
        error != nil
    }

    private(set) static var error: Error?

    static func launch(with error: Error) -> Never {
        self.error = error // 在存在 user default 的情况下 window group 可能不会被使用
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, nil)
        fatalError()
    }

    static func resetApplication() -> Never {
        debugPrint("\(#file) \(#function) \(self)")

        do {
            // make sure sandbox is enabled otherwise panic the app
            let sandboxTestDir = URL(fileURLWithPath: "/tmp/sandbox.test.\(UUID().uuidString)")
            FileManager.default.createFile(atPath: sandboxTestDir.path, contents: nil, attributes: nil)
            if FileManager.default.fileExists(atPath: sandboxTestDir.path) {
                fatalError("this app should not run outside of sandbox which may cause trouble.")
            }
        }

        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.resetStandardUserDefaults()
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        debugPrint(Array(UserDefaults.standard.dictionaryRepresentation().keys).count)

        let directories: [FileManager.SearchPathDirectory] = [
            .documentDirectory,
            .libraryDirectory,
            .cachesDirectory,
            .trashDirectory,
        ]
        for dir in directories.flatMap({ FileManager.default.urls(for: $0, in: .userDomainMask) }) {
            try? FileManager.default.removeItem(at: dir)
        }

        terminateApplication()
    }
}

class RecoveryModeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let powerButton = UIImageView()
        powerButton.image = .init(systemName: "power.circle.fill")
        powerButton.tintColor = .gray.withAlphaComponent(0.025)
        powerButton.contentMode = .scaleAspectFit
        view.addSubview(powerButton)
        powerButton.snp.makeConstraints { x in
            x.height.lessThanOrEqualTo(500)
            x.height.lessThanOrEqualToSuperview().inset(50)
            x.width.lessThanOrEqualTo(500)
            x.width.lessThanOrEqualToSuperview().inset(50)
            x.center.equalToSuperview()
        }

        let recoverText =
            """
            There seems to be a problem with the application. You can reset or restart it.
            Il semble y avoir un problème avec l'application. Vous pouvez la réinitialiser ou la redémarrer.
            Es scheint ein Problem mit der Anwendung zu geben. Sie können sie zurücksetzen oder neu starten.
            Parece que hay un problema con la aplicación. Puedes restablecerla o reiniciarla.
            アプリケーションに問題が発生したようです。リセットまたは再起動を選択できます。
            应用程序似乎出了问题。您可以选择重置或重新启动。

            \(RecoveryMode.error?.localizedDescription ?? "")
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.attributedText = .init(string: recoverText, attributes: [
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineSpacing = 2
                style.paragraphSpacing = 8
                return style
            }(),
            .font: UIFont.preferredFont(forTextStyle: .footnote),
        ])
        view.addSubview(label)
        label.snp.makeConstraints { x in
            x.center.equalToSuperview()
            x.width.lessThanOrEqualTo(350)
            x.width.lessThanOrEqualToSuperview().inset(50)
            x.height.lessThanOrEqualToSuperview().inset(50)
        }

        let resetButton = UIButton()
        resetButton.setImage(.init(systemName: "trash.fill"), for: .normal)
        resetButton.tintColor = .systemRed
        resetButton.addTarget(self, action: #selector(resetApplication), for: .touchUpInside)
        view.addSubview(resetButton)
        resetButton.snp.makeConstraints { x in
            x.left.equalTo(label.snp.left)
            x.top.equalTo(label.snp.bottom).offset(50)
            x.width.equalTo(50)
            x.height.equalTo(50)
        }

        let rebootButton = UIButton()
        rebootButton.setImage(.init(systemName: "stop.fill"), for: .normal)
        rebootButton.tintColor = .systemBlue
        rebootButton.addTarget(self, action: #selector(terminate), for: .touchUpInside)
        view.addSubview(rebootButton)
        rebootButton.snp.makeConstraints { x in
            x.right.equalTo(label.snp.right)
            x.top.equalTo(label.snp.bottom).offset(50)
            x.width.equalTo(50)
            x.height.equalTo(50)
        }
    }

    @objc
    func resetApplication() {
        RecoveryMode.resetApplication()
    }

    @objc func terminate() {
        terminateApplication()
    }
}
