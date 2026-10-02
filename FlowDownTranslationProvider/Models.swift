//
//  Models.swift
//  FlowDownTranslationProvider
//
//  Created by qaq on 13/12/2025.
//

import Foundation
import Storage

func scanModels() -> [CloudModel] {
    guard let dir = AppGroup.sharedCloudModelsURL else {
        assertionFailure()
        return []
    }
    guard let list = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
        return []
    }
    var build = [CloudModel]()
    let decoder = PropertyListDecoder()
    for item in list {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(item)),
              let object = try? decoder.decode(CloudModel.self, from: data)
        else {
            continue
        }
        build.append(object)
    }
    print("[*] scanner reported \(build.count) cloud models")
    return build
}
