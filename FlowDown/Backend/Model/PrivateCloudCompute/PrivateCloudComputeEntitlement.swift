//
//  PrivateCloudComputeEntitlement.swift
//  FlowDown
//
//  Whether this copy of the app was signed with the managed entitlement
//  `com.apple.developer.private-cloud-compute`. Apple grants it only to App
//  Store, TestFlight and development builds; the Developer ID build from
//  GitHub Releases is signed without it (Resources/DevKit/scripts/
//  codesign-macos.sh drops it), so there the model can never run.
//
//  iOS builds only ship through the App Store and TestFlight, so they are
//  taken as entitled. On Mac Catalyst the running process's own code
//  signature is read with SecTask (the script strips the key from the
//  signature, not only from the profile).
//

import Foundation
#if targetEnvironment(macCatalyst)
    import Security
#endif

enum PrivateCloudComputeEntitlement {
    static let key = "com.apple.developer.private-cloud-compute"

    /// Read once per launch; the signature can't change while running.
    static let isGranted: Bool = {
        #if DEBUG
            // Lets a Simulator show the Developer ID state:
            //   simulator launch wiki.qaq.flow --env FLOWDOWN_PCC_ENTITLEMENT=missing
            if ProcessInfo.processInfo.environment[debugEnvironmentKey] == "missing" {
                return false
            }
        #endif
        #if targetEnvironment(macCatalyst)
            // If the signature can't be read, don't take the model away
            // from a build that may well have it.
            return signedValue() ?? true
        #else
            return true
        #endif
    }()

    #if DEBUG
        static let debugEnvironmentKey = "FLOWDOWN_PCC_ENTITLEMENT"
    #endif

    /// Where `isGranted` came from, for the log.
    static var diagnosticDescription: String {
        #if DEBUG
            if ProcessInfo.processInfo.environment[debugEnvironmentKey] == "missing" {
                return "missing (\(debugEnvironmentKey)=missing)"
            }
        #endif
        #if targetEnvironment(macCatalyst)
            switch signedValue() {
            case true?: return "granted (code signature)"
            case false?: return "missing (code signature)"
            case nil: return "assumed granted (code signature unreadable)"
            }
        #else
            return "assumed granted (iOS)"
        #endif
    }

    #if targetEnvironment(macCatalyst)
        /// The entitlement in the running process's code signature, or nil
        /// when it can't be read.
        private static func signedValue() -> Bool? {
            guard let task = SecTaskCreateFromSelf(nil) else { return nil }
            var error: Unmanaged<CFError>?
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error)
            if let error {
                error.release()
                return nil
            }
            return (value as? Bool) ?? false
        }
    #endif
}
