//
//  HubModelDownloadController+RemoteModel.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import BetterCodable
import ConfigurableKit
import Foundation
import UIKit

private enum HubModelFetchError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "invalid response"
        case let .badStatus(code):
            "unexpected http status: \(code)"
        case .invalidPayload:
            "invalid payload"
        }
    }
}

extension HubModelDownloadController {
    struct RemoteModel: Codable, Equatable, Hashable {
        let id: String
        let author: String
        let downloads: Int
        let pipeline_tag: String

        init(id: String, author: String, downloads: Int, pipeline_tag: String) {
            self.id = id
            self.author = author
            self.downloads = downloads
            self.pipeline_tag = pipeline_tag
        }

        init?(dic: [String: Any]) {
            guard let id = dic["id"] as? String, !id.isEmpty else {
                return nil
            }
            self.id = id
            author = dic["author"] as? String ?? ""
            downloads = dic["downloads"] as? Int ?? 0
            pipeline_tag = dic["pipeline_tag"] as? String ?? ""
        }
    }
}

extension HubModelDownloadController {
    func fetchModel(
        keyword: String,
        completion: @escaping ([RemoteModel]) -> Void,
        errorCompletion: ((Error) -> Void)? = nil
    ) {
        searchTask?.cancel()
        searchTask = nil
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "full", value: "full"), // to get author in response
            anchorToVerifiedAuthorMLX ? URLQueryItem(name: "author", value: "mlx-community") : nil,
            anchorToTextGenerationModels ? URLQueryItem(name: "filter", value: "text-generation") : nil,
            URLQueryItem(name: "sort", value: "downloads"),
            keyword.isEmpty ? nil : URLQueryItem(name: "search", value: keyword),
        ].compactMap(\.self)
        guard let url = components.url else {
            errorCompletion?(HubModelFetchError.invalidResponse)
            completion([])
            return
        }
        let request = URLRequest(url: url)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Logger.network.errorFile("[fetchModel] request error: \(error.localizedDescription)")
                Task { @MainActor in
                    errorCompletion?(error)
                    completion([])
                }
                return
            }

            guard let http = response as? HTTPURLResponse else {
                Logger.network.errorFile("[fetchModel] invalid response")
                Task { @MainActor in
                    errorCompletion?(HubModelFetchError.invalidResponse)
                    completion([])
                }
                return
            }

            guard (200 ... 299).contains(http.statusCode) else {
                Logger.network.errorFile("[fetchModel] non-success status: \(http.statusCode)")
                Task { @MainActor in
                    errorCompletion?(HubModelFetchError.badStatus(http.statusCode))
                    completion([])
                }
                return
            }

            guard let data else {
                Logger.network.errorFile("[fetchModel] missing data")
                Task { @MainActor in
                    errorCompletion?(HubModelFetchError.invalidPayload)
                    completion([])
                }
                return
            }

            let dicArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
            let models = dicArray?.compactMap(RemoteModel.init(dic:))
            Task { @MainActor [weak self] in
                guard let self else { return }
                searchTask = nil
                if models == nil {
                    errorCompletion?(HubModelFetchError.invalidPayload)
                }
                completion(models ?? [])
            }
        }
        searchTask = task
        task.resume()
    }
}
