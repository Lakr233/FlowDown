//
//  ModelManager+Cloud.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/28/25.
//

import CommonCrypto
import Foundation
import Storage

private enum CloudModelListFetchError: LocalizedError {
    case modelNotFound
    case invalidEndpoint
    case requestFailed(Error)
    case badStatus(Int)
    case emptyBody
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            "cloud model not found"
        case .invalidEndpoint:
            "invalid model list endpoint"
        case let .requestFailed(error):
            error.localizedDescription
        case let .badStatus(code):
            "unexpected http status: \(code)"
        case .emptyBody:
            "empty response body"
        case .invalidJSON:
            "invalid json response"
        }
    }
}

extension CloudModel {
    var modelDisplayName: String {
        // Use custom name if available
        if !name.isEmpty {
            return name
        }

        var ret = model_identifier
        let scope = scopeIdentifier
        if !scope.isEmpty, ret.hasPrefix(scopeIdentifier + "/") {
            ret.removeFirst(scopeIdentifier.count + 1)
        }
        if ret.isEmpty { ret = String(localized: "Not Configured") }
        return ret
    }

    var modelFullName: String {
        let host = URL(string: endpoint)?.host
        return [
            model_identifier,
            host,
        ].compactMap(\.self).joined(separator: "@")
    }

    var scopeIdentifier: String {
        if model_identifier.contains("/") {
            return model_identifier.components(separatedBy: "/").first ?? ""
        }
        return ""
    }

    var inferenceHost: String {
        URL(string: endpoint)?.host ?? ""
    }

    var auxiliaryIdentifier: String {
        [
            "@",
            inferenceHost,
            scopeIdentifier.isEmpty ? "" : "@\(scopeIdentifier)",
        ].filter { !$0.isEmpty }.joined()
    }

    var tags: [String] {
        var input: [String] = []
        input.append(auxiliaryIdentifier)
        let caps = ModelCapabilities.allCases
            .filter { capabilities.contains($0) }
            .map(\.title)
            .map { String(localized: $0) }
        input.append(contentsOf: caps)
        return input.filter { !$0.isEmpty }
    }
}

extension ModelManager {
    func scanCloudModels() -> [CloudModel] {
        let models: [CloudModel] = sdb.cloudModelList()
        for model in models where model.id.isEmpty {
            // Ensure all models have a valid ID
            model.update(\.objectId, to: UUID().uuidString)
            sdb.cloudModelRemove(identifier: "")
            sdb.cloudModelEdit(identifier: model.objectId) {
                $0.update(\.objectId, to: model.objectId)
            }
            return scanCloudModels()
        }
        return models
    }

    func newCloudModel() -> CloudModel {
        let object = CloudModel(deviceId: Storage.deviceId)
        try? sdb.cloudModelPut(object)
        defer { cloudModels.send(scanCloudModels()) }
        return object
    }

    func newCloudModel(profile: CloudModel) -> CloudModel {
        profile.update(\.objectId, to: UUID().uuidString)
        try? sdb.cloudModelPut(profile)
        defer { cloudModels.send(scanCloudModels()) }
        return profile
    }

    func insertCloudModel(_ model: CloudModel) {
        try? sdb.cloudModelPut(model)
        cloudModels.send(scanCloudModels())
    }

    func cloudModel(identifier: CloudModelIdentifier?) -> CloudModel? {
        guard let identifier else { return nil }
        return sdb.cloudModel(with: identifier)
    }

    func removeCloudModel(identifier: CloudModelIdentifier) {
        sdb.cloudModelRemove(identifier: identifier)
        cloudModels.send(scanCloudModels())
    }

    func editCloudModel(identifier: CloudModelIdentifier?, block: @escaping (inout CloudModel) -> Void) {
        guard let identifier else { return }
        sdb.cloudModelEdit(identifier: identifier, block)
        cloudModels.send(scanCloudModels())
    }

    func fetchModelList(
        identifier: CloudModelIdentifier?,
        block: @escaping ([String]) -> Void,
        errorBlock: ((Error) -> Void)? = nil
    ) {
        guard let model = cloudModel(identifier: identifier) else {
            errorBlock?(CloudModelListFetchError.modelNotFound)
            block([])
            return
        }
        let endpoint = model.endpoint
        var model_list_endpoint = model.model_list_endpoint
        if model_list_endpoint.contains("$INFERENCE_ENDPOINT$") {
            if model.endpoint.isEmpty {
                errorBlock?(CloudModelListFetchError.invalidEndpoint)
                block([])
                return
            }
            model_list_endpoint = model_list_endpoint.replacingOccurrences(of: "$INFERENCE_ENDPOINT$", with: endpoint)
        }
        guard !model_list_endpoint.isEmpty, let url = URL(string: model_list_endpoint)?.standardized else {
            errorBlock?(CloudModelListFetchError.invalidEndpoint)
            block([])
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        if !model.token.isEmpty { request.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization") }
        // model.headers can override default headers including Authorization
        for (key, value) in model.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let deliver: ([String]) -> Void = { input in
            Task { @MainActor in
                block(input)
            }
        }
        let deliverError: (Error) -> Void = { error in
            Task { @MainActor in
                errorBlock?(error)
            }
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Logger.network.errorFile("[fetchModelList] request error: \(error.localizedDescription)")
                deliverError(CloudModelListFetchError.requestFailed(error))
                return deliver([])
            }
            if let http = response as? HTTPURLResponse {
                if !(200 ... 299).contains(http.statusCode) {
                    Logger.network.errorFile("[fetchModelList] non-200 status: \(http.statusCode) for URL: \(url.absoluteString)")
                    deliverError(CloudModelListFetchError.badStatus(http.statusCode))
                    return deliver([])
                }
            }
            guard let data else {
                deliverError(CloudModelListFetchError.emptyBody)
                return deliver([])
            }
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                if let str = String(data: data, encoding: .utf8) {
                    Logger.network.errorFile("[fetchModelList] non-JSON response: \(str.prefix(256))...")
                }
                deliverError(CloudModelListFetchError.invalidJSON)
                return deliver([])
            }
            let value = self.scrubModel(fromDic: json).sorted()
            deliver(value)
        }.resume()
    }

    private func scrubModel(fromDic dic: Any) -> [String] {
        // Common OpenAI-style: { data: [{id: ""}, ...] }
        if let dict = dic as? [String: Any] {
            if let data = dict["data"] as? [[String: Any]] {
                return data.compactMap { $0["id"] as? String }
            }
            if let data = dict["data"] as? [String] {
                return data
            }
            // Some providers: { models: [ { id/name/model: "..." } ] }
            if let models = dict["models"] as? [[String: Any]] {
                return models.compactMap { item in
                    (item["id"] as? String)
                        ?? (item["name"] as? String)
                        ?? (item["model"] as? String)
                }
            }
            if let models = dict["models"] as? [String] {
                return models
            }
            // Generic container: { items: [...] }
            if let items = dict["items"] as? [[String: Any]] {
                return items.compactMap { $0["id"] as? String ?? $0["name"] as? String }
            }
        }
        // Direct arrays
        if let array = dic as? [[String: Any]] {
            return array.compactMap { $0["id"] as? String ?? $0["name"] as? String }
        }
        if let array = dic as? [String] {
            return array
        }
        return []
    }

    func importCloudModel(at url: URL) throws -> CloudModel {
        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: url)
        let model = try decoder.decode(CloudModel.self, from: data)

        // Imported model configurations must be treated as a new local object.
        // Otherwise, an exported file can collide with an existing (or soft-deleted) row and
        // end up being ignored by diffing logic, showing a "success" toast with no visible data.
        model.update(\.deviceId, to: Storage.deviceId)
        model.update(\.objectId, to: UUID().uuidString)
        model.update(\.removed, to: false)

        let now = Date.now
        model.update(\.creation, to: now)
        model.update(\.modified, to: now)

        insertCloudModel(model)
        return model
    }
}
