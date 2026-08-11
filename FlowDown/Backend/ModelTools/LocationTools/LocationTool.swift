//
//  LocationTool.swift
//  FlowDown
//
//  Created on 2/28/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import CoreLocation
import Foundation
import UIKit

class MTLocationTool: ModelTool, @unchecked Sendable {
    private var locationManager: CLLocationManager?
    private var geocoder = CLGeocoder()

    private var locationCompletion: ((String, Bool) -> Void)?
    private var loadingIndicator: AlertProgressIndicatorViewController?
    private var currentLocale: Locale?

    override var interfaceName: String {
        String(localized: "Current Location")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "get_current_location",
            description:
            "Get the user's current location as a structured address: country, city, street and postal code where available.",
            parameters: [
                "type": "object",
                "properties": [
                    "locale": [
                        "type": "string",
                        "description": "Locale for address formatting, e.g. \"en_US\". Pass an empty string for the system locale.",
                    ],
                ],
                "required": ["locale"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "location.circle",
            title: "Location Access",
            explain: "Allows LLM to access your current location information.",
            key: "wiki.qaq.ModelTools.LocationTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        var locale: Locale = .current

        // 解析输入参数
        if !input.isEmpty,
           let json = decodeArguments(input),
           let localeIdentifier = json["locale"] as? String
        {
            locale = Locale(identifier: localeIdentifier)
        }

        let viewController = try await anchorController(for: view)

        return try await requestLocationWithUserInteraction(
            controller: viewController, locale: locale,
        )
    }

    @MainActor
    func requestLocationWithUserInteraction(controller: UIViewController, locale: Locale) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            // App Store Review said don't ask for that
            self.getLocationAndAddress(controller: controller, locale: locale) { result, isSuccess in
                if isSuccess {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "Tool", code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: result,
                        ],
                    ))
                }
            }
        }
    }

    private func getLocationAndAddress(
        controller: UIViewController, locale: Locale, completion: @escaping (String, Bool) -> Void,
    ) {
        var isCompletionCalled = false
        let wrappedCompletion: (String, Bool) -> Void = { text, success in
            guard !isCompletionCalled else { return }
            isCompletionCalled = true
            completion(text, success)
        }

        let indicator = AlertProgressIndicatorViewController(
            title: "Retrieving Location",
        )

        controller.present(indicator, animated: true)

        // 创建位置管理器
        locationManager = CLLocationManager()
        locationManager?.delegate = self // 设置代理
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters // 设置精度

        locationCompletion = wrappedCompletion
        loadingIndicator = indicator
        currentLocale = locale

        Task.detached { [weak self] in
            guard let self else { return }
            if CLLocationManager.locationServicesEnabled() {
                await MainActor.run {
                    guard let manager = self.locationManager else {
                        indicator.dismiss(animated: true) {
                            wrappedCompletion(String(localized: "Could not initialize location services."), false)
                        }
                        return
                    }

                    switch manager.authorizationStatus {
                    case .notDetermined:
                        self.locationManager?.requestWhenInUseAuthorization()
                        return

                    case .denied, .restricted:
                        indicator.dismiss(animated: true) {
                            wrappedCompletion(
                                String(
                                    localized:
                                    "Location access is not available. Please check your device settings.",
                                ), false,
                            )
                        }
                        return

                    case .authorizedWhenInUse, .authorizedAlways:
                        break

                    @unknown default:
                        indicator.dismiss(animated: true) {
                            wrappedCompletion(
                                String(localized: "Unknown authorization status for location services."), false,
                            )
                        }
                        return
                    }

                    self.performLocationLookup()
                }
            } else {
                await MainActor.run {
                    indicator.dismiss(animated: true) {
                        wrappedCompletion(String(localized: "Location services are disabled on this device."), false)
                    }
                }
            }
        }
    }

    private func performLocationLookup() {
        guard let indicator = loadingIndicator,
              let completion = locationCompletion,
              let locale = currentLocale
        else {
            loadingIndicator?.dismiss(animated: true) {
                self.locationCompletion?(String(localized: "Could not determine current location."), false)
            }
            return
        }

        // 获取当前位置
        if let location = locationManager?.location {
            // 地理编码
            geocoder.reverseGeocodeLocation(location, preferredLocale: locale) {
                placemarks, error in
                indicator.dismiss(animated: true) {
                    if let error {
                        completion(
                            String(
                                localized:
                                "Error getting location details: \(error.localizedDescription)",
                            ), false,
                        )
                        return
                    }

                    guard let placemark = placemarks?.first else {
                        completion(String(localized: "No location details found."), false)
                        return
                    }

                    // 格式化位置信息
                    var addressComponents = [String]()

                    // 坐标
                    let latitude = location.coordinate.latitude
                    let longitude = location.coordinate.longitude
                    addressComponents.append(
                        String(
                            localized:
                            "Coordinates: \(String(format: "%.6f", latitude)), \(String(format: "%.6f", longitude))",
                        ),
                    )

                    if let name = placemark.name, !name.isEmpty {
                        addressComponents.append(String(localized: "Name: \(name)"))
                    }

                    if let thoroughfare = placemark.thoroughfare {
                        var street = thoroughfare
                        if let subThoroughfare = placemark.subThoroughfare {
                            street = subThoroughfare + " " + thoroughfare
                        }
                        addressComponents.append(String(localized: "Street: \(street)"))
                    }

                    if let locality = placemark.locality {
                        addressComponents.append(String(localized: "City: \(locality)"))
                    }

                    if let administrativeArea = placemark.administrativeArea {
                        addressComponents.append(
                            String(localized: "State/Province: \(administrativeArea)"),
                        )
                    }

                    if let postalCode = placemark.postalCode {
                        addressComponents.append(
                            String(localized: "Postal Code: \(postalCode)"),
                        )
                    }

                    if let country = placemark.country {
                        addressComponents.append(String(localized: "Country: \(country)"))
                    }

                    if let isoCountryCode = placemark.isoCountryCode {
                        addressComponents.append(
                            String(localized: "Country Code: \(isoCountryCode)"),
                        )
                    }

                    if let timeZone = placemark.timeZone?.identifier {
                        addressComponents.append(String(localized: "Time Zone: \(timeZone)"))
                    }

                    let result = String(
                        localized: """
                        Current Location Information:

                        \(addressComponents.joined(separator: "\n"))
                        """,
                    )

                    completion(result, true)
                }
            }
        } else {
            indicator.dismiss(animated: true) {
                completion(String(localized: "Could not determine current location."), false)
            }
        }
    }
}

extension MTLocationTool: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            performLocationLookup()

        case .denied, .restricted:
            loadingIndicator?.dismiss(animated: true) {
                self.locationCompletion?(String(localized: "Location access denied by user."), false)
            }

        case .notDetermined:
            break

        @unknown default:
            loadingIndicator?.dismiss(animated: true) {
                self.locationCompletion?(
                    String(localized: "Unknown authorization status for location services."), false,
                )
            }
        }
    }
}
