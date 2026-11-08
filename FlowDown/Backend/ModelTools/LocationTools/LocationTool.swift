//
//  LocationTool.swift
//  FlowDown
//
//  Created on 2/28/25.
//

import ChatClientKit
import ConfigurableKit
import CoreLocation
import Foundation

final class MTLocationTool: NSObject, ConfigurableModelTool, @unchecked Sendable {
    private var locationManager: CLLocationManager?
    private let geocoder = CLGeocoder()

    private var locationCompletion: ((String, Bool) -> Void)?
    private var currentLocale: Locale?
    private var isGeocoding = false

    var interfaceName: String {
        String(localized: "Current Location")
    }

    var definition: ChatRequestBody.Tool {
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

    static var controlObject: ConfigurableObject {
        .init(
            icon: "location.circle",
            title: "Location Access",
            explain: "Allows LLM to access your current location information.",
            key: "wiki.qaq.ModelTools.LocationTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var access: ModelToolAccess {
        .privateData
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        var locale: Locale = .current
        if let localeIdentifier = arguments.string("locale"), !localeIdentifier.isEmpty {
            locale = Locale(identifier: localeIdentifier)
        }

        // The system answers this synchronously and can stall the main
        // thread, so ask before hopping there.
        guard CLLocationManager.locationServicesEnabled() else {
            throw ModelToolError.failure(String(localized: "Location services are disabled on this device."))
        }

        let text = try await requestLocation(locale: locale)
        return ModelToolOutput(text: text)
    }

    /// Starts a one-shot lookup on the main actor, where the location manager
    /// delivers its callbacks, and waits for the address.
    @MainActor
    private func requestLocation(locale: Locale) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            // Both the authorization callback and the explicit check below can
            // finish the lookup; only the first answer counts.
            var isCompletionCalled = false
            locationCompletion = { text, success in
                guard !isCompletionCalled else { return }
                isCompletionCalled = true
                if success {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: ModelToolError.failure(text))
                }
            }
            currentLocale = locale
            isGeocoding = false

            let manager = CLLocationManager()
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager = manager

            // App Store Review said don't ask for that
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()

            case .denied, .restricted:
                locationCompletion?(
                    String(
                        localized:
                        "Location access is not available. Please check your device settings.",
                    ),
                    false,
                )

            case .authorizedWhenInUse, .authorizedAlways:
                performLocationLookup()

            @unknown default:
                locationCompletion?(
                    String(localized: "Unknown authorization status for location services."),
                    false,
                )
            }
        }
    }

    private func performLocationLookup() {
        guard let completion = locationCompletion,
              let locale = currentLocale
        else {
            locationCompletion?(String(localized: "Could not determine current location."), false)
            return
        }

        // Both the authorization callback and the explicit check land here;
        // a second request on the same geocoder would cancel the first.
        guard !isGeocoding else { return }

        guard let location = locationManager?.location else {
            // `location` only holds a cached fix, which is nil until the app
            // has received one; ask for a fresh fix and continue from the
            // delegate once it arrives.
            locationManager?.requestLocation()
            return
        }

        isGeocoding = true
        geocoder.reverseGeocodeLocation(location, preferredLocale: locale) { placemarks, error in
            if let error {
                completion(
                    String(
                        localized:
                        "Error getting location details: \(error.localizedDescription)",
                    ),
                    false,
                )
                return
            }

            guard let placemark = placemarks?.first else {
                completion(String(localized: "No location details found."), false)
                return
            }

            completion(Self.describe(placemark, at: location), true)
        }
    }

    /// The address the model reads, one labelled field per line.
    private static func describe(_ placemark: CLPlacemark, at location: CLLocation) -> String {
        var addressComponents = [String]()

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

        return String(
            localized: """
            Current Location Information:

            \(addressComponents.joined(separator: "\n"))
            """,
        )
    }
}

extension MTLocationTool: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            performLocationLookup()

        case .denied, .restricted:
            locationCompletion?(String(localized: "Location access denied by user."), false)

        case .notDetermined:
            break

        @unknown default:
            locationCompletion?(
                String(localized: "Unknown authorization status for location services."),
                false,
            )
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        performLocationLookup()
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        guard !isGeocoding else { return }
        locationCompletion?(String(localized: "Could not determine current location."), false)
    }
}
