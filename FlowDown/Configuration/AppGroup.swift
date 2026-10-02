//
//  AppGroup.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import Foundation

enum AppGroup {
    static let identifier = "group.wiki.qaq"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier,
        )
    }

    static var sharedCloudModelsURL: URL? {
        containerURL?
            .appendingPathComponent("FlowDown")
            .appendingPathComponent("Models")
            .appendingPathComponent("Cloud")
    }

    /// The app writes this file and FlowDownTranslationProvider, which links this source file, reads it.
    static var sharedAdditionalPromptURL: URL? {
        containerURL?
            .appendingPathComponent("FlowDown")
            .appendingPathComponent("Prompts")
            .appendingPathComponent("Additional.txt")
    }
}
