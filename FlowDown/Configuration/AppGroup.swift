//
//  AppGroup.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import Foundation

enum AppGroup {
    private static let identifier = "group.wiki.qaq"

    private static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier,
        )
    }

    private static var flowDownDirectoryURL: URL? {
        containerURL?.appendingPathComponent("FlowDown")
    }

    static var sharedCloudModelsURL: URL? {
        flowDownDirectoryURL?
            .appendingPathComponent("Models")
            .appendingPathComponent("Cloud")
    }

    /// The app writes this file and FlowDownTranslationProvider, which links this source file, reads it.
    static var sharedAdditionalPromptURL: URL? {
        flowDownDirectoryURL?
            .appendingPathComponent("Prompts")
            .appendingPathComponent("Additional.txt")
    }
}
