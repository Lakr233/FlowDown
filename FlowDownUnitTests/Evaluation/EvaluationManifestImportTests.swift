//
//  EvaluationManifestImportTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import Testing

struct EvaluationManifestImportTests {
    @Test
    func manifestImport_undecodableFile_throws() {
        let data = Data(#"{"title":"x"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try EvaluationAssistantController.decodeImportedManifests(from: data)
        }
    }

    @Test
    func manifestImport_singleManifest_decodes() throws {
        let manifest = EvaluationManifest(title: "Imported", description: "", suites: [])
        let data = try JSONEncoder().encode(manifest)
        let decoded = try EvaluationAssistantController.decodeImportedManifests(from: data)
        #expect(decoded.count == 1)
    }

    @Test
    func manifestImport_manifestList_decodes() throws {
        let manifests = [
            EvaluationManifest(title: "First", description: "", suites: []),
            EvaluationManifest(title: "Second", description: "", suites: []),
        ]
        let data = try JSONEncoder().encode(manifests)
        let decoded = try EvaluationAssistantController.decodeImportedManifests(from: data)
        #expect(decoded.count == 2)
    }
}
