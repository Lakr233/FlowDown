//
//  ModelDescribing.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/12/26.
//

import Foundation
import Storage

/// The shape shared by every configured model, wherever it runs. Local and
/// cloud models derive their scope, grouping key and tag list identically; only
/// the inference host and the display name differ.
protocol ModelDescribing {
    var model_identifier: String { get }
    var capabilities: Set<ModelCapabilities> { get }
    /// Host the inference runs against, used to group models in menus.
    var inferenceHost: String { get }
}

extension ModelDescribing {
    /// Publisher prefix of an `owner/name` style identifier, empty when absent.
    var scopeIdentifier: String {
        guard model_identifier.contains("/") else { return "" }
        return model_identifier.components(separatedBy: "/").first ?? ""
    }

    /// Identifier suffix that disambiguates models sharing a name.
    var auxiliaryIdentifier: String {
        [
            "@",
            inferenceHost,
            scopeIdentifier.isEmpty ? "" : "@\(scopeIdentifier)",
        ].filter { !$0.isEmpty }.joined()
    }

    var tags: [String] {
        var input: [String] = [auxiliaryIdentifier]
        input.append(contentsOf: ModelCapabilities.allCases
            .filter { capabilities.contains($0) }
            .map(\.title)
            .map { String(localized: $0) })
        return input.filter { !$0.isEmpty }
    }

    /// Model name without the publisher prefix.
    var scopelessModelName: String {
        var ret = model_identifier
        if !scopeIdentifier.isEmpty, ret.hasPrefix(scopeIdentifier + "/") {
            ret.removeFirst(scopeIdentifier.count + 1)
        }
        if ret.isEmpty { ret = String(localized: "Not Configured") }
        return ret
    }
}

extension LocalModel: ModelDescribing {
    var inferenceHost: String { "localhost" }
}

extension CloudModel: ModelDescribing {
    var inferenceHost: String { URL(string: endpoint)?.host ?? "" }
}
