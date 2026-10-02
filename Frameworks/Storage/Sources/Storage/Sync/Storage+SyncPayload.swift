//
//  Storage+SyncPayload.swift
//  Storage
//

import Compression
import Foundation

private enum SyncPayloadCoder {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64
        return decoder
    }()
}

// MARK: - Sync

struct FlowDownPayloadHeader {
    static let CompressionThreshold: Int = 1024
    static let magic: [UInt8] = [0x46, 0x6C, 0x6F, 0x77, 0x44, 0x6F, 0x77, 0x6E] // "FlowDown"
    static let version: UInt8 = 1

    enum Algorithm: UInt8, CaseIterable {
        case none = 0
        case lzfse = 1
        case zlib = 2
        case lz4 = 3
        case lzma = 4

        var compressionAlgorithm: compression_algorithm? {
            switch self {
            case .lzfse: COMPRESSION_LZFSE
            case .zlib: COMPRESSION_ZLIB
            case .lz4: COMPRESSION_LZ4
            case .lzma: COMPRESSION_LZMA
            case .none: nil
            }
        }
    }

    var compressionAlgorithm: Algorithm

    /// 序列化为 Data
    func encode() -> Data {
        var data = Data(FlowDownPayloadHeader.magic)
        data.append(FlowDownPayloadHeader.version)
        data.append(compressionAlgorithm.rawValue)
        return data
    }

    /// 从 Data 解析 header
    static func decode(from data: Data) throws -> (header: FlowDownPayloadHeader, payloadOffset: Int) {
        guard data.count >= 10 else {
            throw NSError(
                domain: "CompressionHeader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Data too short"]
            )
        }

        let magic = Array(data[0 ..< 8])
        guard magic == FlowDownPayloadHeader.magic else {
            throw NSError(
                domain: "CompressionHeader",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid magic number"]
            )
        }

        let version = data[8]
        guard version == FlowDownPayloadHeader.version else {
            throw NSError(
                domain: "CompressionHeader",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported version"]
            )
        }

        let algorithmByte = data[9]
        guard let alg = Algorithm(rawValue: algorithmByte) else {
            throw NSError(
                domain: "CompressionHeader",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Unknown algorithm"]
            )
        }

        return (FlowDownPayloadHeader(compressionAlgorithm: alg), 10)
    }
}

extension Storage {
    static func encodePayloadSyncable(_ value: some Codable) throws -> Data {
        let plistData = try SyncPayloadCoder.encoder.encode(value)

        var header = FlowDownPayloadHeader(compressionAlgorithm: FlowDownPayloadHeader.Algorithm.none)
        if plistData.count >= FlowDownPayloadHeader.CompressionThreshold, let compressed = plistData.compressed(using: COMPRESSION_LZFSE) {
            header.compressionAlgorithm = FlowDownPayloadHeader.Algorithm.lzfse
            let headerData = header.encode()
            var result = Data(headerData)
            result.append(compressed)
            return result
        } else {
            let headerData = header.encode()
            var result = Data(headerData)
            result.append(plistData)
            return result
        }
    }

    static func decodePayloadSyncable<T: Codable>(_: T.Type, _ data: Data) throws -> T {
        guard !data.isEmpty else {
            throw NSError(
                domain: "Storage.decodePayloadSyncable",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "Empty data"]
            )
        }

        let (header, offset) = try FlowDownPayloadHeader.decode(from: data)
        let payload = data.subdata(in: offset ..< data.count)

        let plistData: Data
        if let alg = header.compressionAlgorithm.compressionAlgorithm {
            guard let decompressed = payload.decompressed(using: alg) else {
                throw NSError(
                    domain: "Storage.decodePayloadSyncable",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Decompression failed"]
                )
            }
            plistData = decompressed
        } else {
            plistData = payload
        }

        return try SyncPayloadCoder.decoder.decode(T.self, from: plistData)
    }
}
