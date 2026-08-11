//
//  AttachmentDataParser.swift
//  FlowDown
//
//  Created by GPT-5 Codex on 2025/12/06.
//

import Foundation

enum AttachmentDataParser {
    /// Decode data from common string encodings (data URLs, base64, plain text).
    static func decodeData(from dataString: String) -> Data? {
        // Handle data URL format: data:image/png;base64,<base64_string>
        if dataString.hasPrefix("data:") {
            return decodeDataURL(dataString)
        }

        // Handle URL string (for data URLs parsed as URL, e.g. an upper-cased scheme)
        if let url = URL(string: dataString), url.scheme == "data" {
            return decodeDataURL(url.absoluteString)
        }

        // Try as direct base64 string (most common case for MCP tools)
        if let data = Data(base64Encoded: dataString, options: .ignoreUnknownCharacters) {
            return data
        }

        // Fallback: treat as UTF-8 string data (should rarely happen)
        return dataString.data(using: .utf8)
    }

    /// Extracts the payload of a `data:` URL, which is either base64 encoded
    /// after `;base64,` or written inline after the first comma.
    private static func decodeDataURL(_ dataString: String) -> Data? {
        if let base64Range = dataString.range(of: ";base64,") {
            return Data(base64Encoded: String(dataString[base64Range.upperBound...]))
        }
        if let commaIndex = dataString.firstIndex(of: ",") {
            // Try base64 first, then fallback to URL-encoded or plain text
            let afterComma = String(dataString[dataString.index(after: commaIndex)...])
            return Data(base64Encoded: afterComma) ?? afterComma.data(using: .utf8)
        }
        return nil
    }
}
