import Foundation

public struct URLBuilder {
    private let baseURL: URL
    private var queryItems: [URLQueryItem] = []

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public mutating func addQueryItem(name: String, value: String?) {
        guard let value, !value.isEmpty else { return }
        queryItems.append(URLQueryItem(name: name, value: value))
    }

    public mutating func addQueryItems(_ items: [String: String]) {
        for (name, value) in items {
            addQueryItem(name: name, value: value)
        }
    }

    public func build() -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url
    }
}
