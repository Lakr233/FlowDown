//
//  SettingContent+Permission.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/24/25.
//

import AVKit
import ConfigurableKit
import CoreLocation
import EventKit
import Network
import Speech
import Storage
import UIKit

extension SettingController.SettingContent {
    class PermissionController: StackScrollController {
        init() {
            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Permission List")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        let cameraUsage = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "camera"))
            $0.configure(title: "Camera")
            $0.configure(description: "We use your camera to take picture. Your photo may be uploaded by your choice.")
        }

        let microphoneUsage = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "mic"))
            $0.configure(title: "Microphone")
            $0.configure(description: "We use your audio data for speech recognition. Your data is processed by system; we do not collect that information.")
        }

        let speechRecognizeUsage = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "waveform"))
            $0.configure(title: "Speech Recognition")
            $0.configure(description: "We use your audio data for speech recognition. Your data is processed by system; we do not collect that information.")
        }

        let lanUsage = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "network"))
            $0.configure(title: "Local Area Network")
            $0.configure(description: "We require LAN access to interact with local service providers. We do not collect any information from your LAN.")
        }

        let calendarUsage = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "calendar"))
            $0.configure(title: "Calendar")
            $0.configure(description: "We use calendar access to allow the assistant to view, create and modify events in your calendar. Calendar data is only accessed when you explicitly use calendar-related features.")
        }

        let locationUsage = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "location.circle"))
            $0.configure(title: "Location")
            $0.configure(description: "We use your location data to provide location-based services when requested. Your location is only accessed when you explicitly use location-related features.")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
            navigationItem.rightBarButtonItem = .init(systemItem: .refresh, primaryAction: .init { _ in
                self.updateValues()
                Indicator.present(
                    title: "Refreshed",
                    referencingView: self.view,
                )
            })
        }

        override func setupContentViews() {
            super.setupContentViews()

            #if !targetEnvironment(macCatalyst)
                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionHeaderView().with(
                        header: "Media",
                    ),
                ) { $0.bottom /= 2 }
                stackView.addArrangedSubview(SeparatorView())

                stackView.addArrangedSubviewWithMargin(cameraUsage)
                stackView.addArrangedSubview(SeparatorView())
            #endif

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Audio",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(microphoneUsage)
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(speechRecognizeUsage)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "We have requested your system to prioritize local processing of your audio data. However, there still remains a possibility that your audio data may be sent to Apple’s servers for processing. We are unable to determine whether your data has been sent to Apple’s servers.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Calendar",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(calendarUsage)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "Please note that if you use cloud-based models to process your request, your data may be sent to your service provider.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            #if !targetEnvironment(macCatalyst)
                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionHeaderView().with(
                        header: "Location",
                    ),
                ) { $0.bottom /= 2 }
                stackView.addArrangedSubview(SeparatorView())
                stackView.addArrangedSubviewWithMargin(locationUsage)
                stackView.addArrangedSubview(SeparatorView())

                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionFooterView().with(
                        footer: "Please note that if you use cloud-based models to process your request, your data may be sent to your service provider.",
                    ),
                ) { $0.top /= 2 }
                stackView.addArrangedSubview(SeparatorView())
            #endif

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Network",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            lanUsage.configure(value: String(localized: "Check"))
            lanUsage.setTapBlock { view in
                let name = ProcessInfo.processInfo.hostName
                if name.isEmpty || name.lowercased() == "localhost" {
                    view.configure(value: String(localized: "Unable to Determine"), isDestructive: true)
                    view.setTapBlock { view in
                        view.valueLabel.menu = UIMenu(children: [
                            UIAction(title: String(localized: "Open Setting")) { _ in
                                UIApplication.shared.openSettings()
                            },
                        ])
                        view.valueLabel.showsMenuAsPrimaryAction = true
                    }
                } else {
                    view.configure(value: String(localized: "Authorized"))
                    view.setTapBlock { _ in
                        Indicator.present(
                            title: "Authorized",
                            referencingView: view,
                        )
                    }
                }
            }
            stackView.addArrangedSubviewWithMargin(lanUsage)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Shortcuts",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            let openSetting = ConfigurableActionView { _ in
                UIApplication.shared.openSettings()
            }.with {
                $0.configure(icon: UIImage(systemName: "gearshape"))
                $0.configure(title: "Open Setting")
                $0.configure(description: "Open the setting page.")
            }
            stackView.addArrangedSubviewWithMargin(openSetting)
            stackView.addArrangedSubview(SeparatorView())

            #if !targetEnvironment(macCatalyst)
                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionFooterView().with(
                        footer: "You can grant unrestricted pasteboard access in Settings for convenience.",
                    ),
                ) {
                    $0.top /= 2
                    $0.bottom = 0
                }
            #endif
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "To change the language used by the software, please go to the system settings.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            updateValues()
        }

        func updateValues() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                cameraUsage.configure(value: String(localized: "Authorized"))
                cameraUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .notDetermined:
                cameraUsage.configure(value: String(localized: "Not Determined"))
                cameraUsage.setTapBlock { _ in
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        Task { @MainActor in self.updateValues() }
                    }
                }
            case .restricted:
                cameraUsage.configure(value: String(localized: "Restricted"))
                cameraUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .denied:
                cameraUsage.configure(value: String(localized: "Denied"), isDestructive: true)
                cameraUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            @unknown default:
                cameraUsage.configure(value: String(localized: "Unknown"))
                cameraUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            }

            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                microphoneUsage.configure(value: String(localized: "Authorized"))
                microphoneUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .notDetermined:
                microphoneUsage.configure(value: String(localized: "Not Determined"))
                microphoneUsage.setTapBlock { _ in
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        Task { @MainActor in self.updateValues() }
                    }
                }
            case .restricted:
                microphoneUsage.configure(value: String(localized: "Restricted"))
                microphoneUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .denied:
                microphoneUsage.configure(value: String(localized: "Denied"), isDestructive: true)
                microphoneUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            @unknown default:
                microphoneUsage.configure(value: String(localized: "Unknown"))
                microphoneUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            }

            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                speechRecognizeUsage.configure(value: String(localized: "Authorized"))
                speechRecognizeUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .notDetermined:
                speechRecognizeUsage.configure(value: String(localized: "Not Determined"))
                speechRecognizeUsage.setTapBlock { _ in
                    SFSpeechRecognizer.requestAuthorization { _ in
                        Task { @MainActor in self.updateValues() }
                    }
                }
            case .restricted:
                speechRecognizeUsage.configure(value: String(localized: "Restricted"))
                speechRecognizeUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .denied:
                speechRecognizeUsage.configure(value: String(localized: "Denied"), isDestructive: true)
                speechRecognizeUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            @unknown default:
                speechRecognizeUsage.configure(value: String(localized: "Unknown"))
                speechRecognizeUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            }

            // 检查日历权限
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized:
                calendarUsage.configure(value: String(localized: "Authorized"))
                calendarUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .notDetermined:
                calendarUsage.configure(value: String(localized: "Not Determined"))
                calendarUsage.setTapBlock { [weak self] _ in
                    let eventStore = EKEventStore()
                    if #available(iOS 17, macCatalyst 17, *) {
                        eventStore.requestFullAccessToEvents { _, _ in
                            Task { @MainActor in self?.updateValues() }
                        }
                    } else {
                        eventStore.requestAccess(to: .event) { _, _ in
                            Task { @MainActor in self?.updateValues() }
                        }
                    }
                }
            case .restricted:
                calendarUsage.configure(value: String(localized: "Restricted"))
                calendarUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .denied:
                calendarUsage.configure(value: String(localized: "Denied"), isDestructive: true)
                calendarUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .fullAccess:
                calendarUsage.configure(value: String(localized: "Full Access"), isDestructive: true)
                calendarUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .writeOnly:
                calendarUsage.configure(value: String(localized: "Write Only"), isDestructive: true)
                calendarUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            @unknown default:
                calendarUsage.configure(value: String(localized: "Unknown"))
                calendarUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            }

            // 检查位置权限 - 使用实例方法而非静态方法
            let locationManager = CLLocationManager()
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                locationUsage.configure(value: String(localized: "Authorized"))
                locationUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .notDetermined:
                locationUsage.configure(value: String(localized: "Not Determined"))
                locationUsage.setTapBlock { _ in
                    locationManager.requestWhenInUseAuthorization()
                    Task { @MainActor in self.updateValues() }
                }
            case .restricted:
                locationUsage.configure(value: String(localized: "Restricted"))
                locationUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            case .denied:
                locationUsage.configure(value: String(localized: "Denied"), isDestructive: true)
                locationUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            @unknown default:
                locationUsage.configure(value: String(localized: "Unknown"))
                locationUsage.setTapBlock { _ in UIApplication.shared.openSettings() }
            }
        }
    }
}
