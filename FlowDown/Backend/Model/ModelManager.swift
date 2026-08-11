//
//  ModelManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import AlertController
import ChatClientKit
import Combine
import ConfigurableKit
import Foundation
import MLX
import OrderedCollections
import Storage
import UIKit

class ModelManager: NSObject {
    static let shared = ModelManager()
    static let flowdownModelConfigurationExtension = "fdmodel"
    static let appleIntelligenceEnabledKey = "Model.Inference.AppleIntelligence.Enabled"

    typealias ModelIdentifier = String
    typealias LocalModelIdentifier = LocalModel.ID
    typealias CloudModelIdentifier = CloudModel.ID
    typealias ChatServiceFactory = (_ identifier: ModelIdentifier, _ additionalBodyField: [String: Any]) throws -> any ChatService

    let localModelDir: URL
    let localModelDownloadTempDir: URL

    var localModels: CurrentValueSubject<[LocalModel], Never> = .init([])
    var cloudModels: CurrentValueSubject<[CloudModel], Never> = .init([])

    let modelChangedPublisher: PassthroughSubject<Void, Never> = .init()

    let encoder = PropertyListEncoder()
    let decoder = PropertyListDecoder()

    var chatServiceFactory: ChatServiceFactory?
    var gpuSupportProvider: () -> Bool = { MLX.GPU.isSupported }
    var dateProvider: () -> Date = { Date() }

    @TypedStorage(key: "Model.Inference.Prompt.Default", defaultValue: PromptType.complete)
    var defaultPrompt: PromptType
    @TypedStorage(key: "Model.Inference.Prompt.Additional", defaultValue: "")
    var additionalPrompt: String
    @TypedStorage(key: "Model.Inference.Prompt.Temperature", defaultValue: 0.75)
    var temperature: Float
    @TypedStorage(key: "Model.Inference.SearchSensitivity", defaultValue: SearchSensitivity.balanced)
    var searchSensitivity: SearchSensitivity

    @TypedStorage(
        key: ModelManager.appleIntelligenceEnabledKey,
        defaultValue: true,
    )
    var appleIntelligenceEnabled: Bool

    @TypedStorage(key: "Model.Default.Conversation", defaultValue: "")
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForConversation: String {
        didSet { checkDefaultModels() }
    }

    @TypedStorage(key: "Model.Default.Auxiliary.UseCurrentChatModel", defaultValue: true)
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForAuxiliaryTaskWillUseCurrentChatModel: Bool {
        didSet { checkDefaultModels() }
    }

    @TypedStorage(key: "Model.Default.Auxiliary", defaultValue: "")
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForAuxiliaryTask: String {
        didSet { checkDefaultModels() }
    }

    @TypedStorage(key: "Model.Default.AuxiliaryVisual", defaultValue: "")
    // swiftformat:disable:next redundantFileprivate
    fileprivate var defaultModelForAuxiliaryVisualTask: String {
        didSet { checkDefaultModels() }
    }

    @TypedStorage(key: "Model.Default.AuxiliaryVisual.SkipIfPossible", defaultValue: true)
    // swiftformat:disable:next redundantFileprivate
    var defaultModelForAuxiliaryVisualTaskSkipIfPossible: Bool
    var defaultModelForAuxiliaryVisualTaskSkipIfPossibleKey: String {
        _defaultModelForAuxiliaryVisualTaskSkipIfPossible.key
    }

    @TypedStorage(key: "Model.ChatInterface.CollapseReasoningSectionWhenComplete", defaultValue: false)
    var collapseReasoningSectionWhenComplete: Bool
    var collapseReasoningSectionWhenCompleteKey: String {
        _collapseReasoningSectionWhenComplete.key
    }

    @TypedStorage(key: "Model.ChatInterface.IncludeDynamicSystemInfo", defaultValue: true)
    var includeDynamicSystemInfo: Bool
    var includeDynamicSystemInfoKey: String {
        _includeDynamicSystemInfo.key
    }

    var cancellables: Set<AnyCancellable> = []

    override private convenience init() {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        self.init(
            localModelDir: base.appendingPathComponent("Models.Local"),
            localModelDownloadTempDir: base.appendingPathComponent("Models.Local.Temp"),
        )
    }

    init(
        localModelDir: URL,
        localModelDownloadTempDir: URL,
    ) {
        assert(LocalModelIdentifier.self == ModelIdentifier.self)
        assert(CloudModelIdentifier.self == ModelIdentifier.self)

        self.localModelDir = localModelDir
        self.localModelDownloadTempDir = localModelDownloadTempDir

        super.init()

        try? FileManager.default.createDirectory(
            at: localModelDir,
            withIntermediateDirectories: true,
            attributes: nil,
        )
        try? FileManager.default.createDirectory(
            at: localModelDownloadTempDir,
            withIntermediateDirectories: true,
            attributes: nil,
        )

        localModels.send(scanLocalModels())
        cloudModels.send(scanCloudModels())

        // make sure after scan!
        Publishers.CombineLatest(
            localModels,
            cloudModels,
        )
        .ensureMainThread()
        .sink { [weak self] _ in
            self?.modelChangedPublisher.send(())
            self?.checkDefaultModels()
        }
        .store(in: &cancellables)

        cloudModels
            .throttle(for: .seconds(1), scheduler: DispatchQueue.global(), latest: true)
            .sink { [weak self] _ in
                self?.dumpEligibleModelsToAppGroup()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.CloudModelChanged)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.CloudModelChanged")
                guard let self else { return }
                cloudModels.send(scanCloudModels())
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.LocalDataDeleted)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.LocalDataDeleted")
                guard let self else { return }
                cloudModels.send(scanCloudModels())
            }
            .store(in: &cancellables)

        Self.defaultPromptConfigurableObject.whenValueChange(type: PromptType.RawValue.self) { [weak self] output in
            guard let output, let value = PromptType(rawValue: output) else { return }
            self?.defaultPrompt = value
        }
        Self.temperatureConfigurableObject.whenValueChange(type: Float.self) { [weak self] output in
            self?.temperature = output ?? 0.75
        }
    }

    func checkDefaultModels() {
        defer { modelChangedPublisher.send() }

        let appleIntelligenceId: String? = if #available(iOS 26.0, macCatalyst 26.0, *) {
            AppleIntelligenceModel.shared.modelIdentifier
        } else {
            nil
        }
        if !defaultModelForConversation.isEmpty,
           localModel(identifier: defaultModelForConversation) == nil,
           cloudModel(identifier: defaultModelForConversation) == nil,
           !(appleIntelligenceId != nil && defaultModelForConversation == appleIntelligenceId)
        {
            Logger.model.debugFile("reset defaultModelForConversation due to not found")
            defaultModelForConversation = ""
        }

        if !defaultModelForAuxiliaryTask.isEmpty,
           localModel(identifier: defaultModelForAuxiliaryTask) == nil,
           cloudModel(identifier: defaultModelForAuxiliaryTask) == nil,
           !(appleIntelligenceId != nil && defaultModelForAuxiliaryTask == appleIntelligenceId)
        {
            Logger.model.debugFile("reset defaultModelForAuxiliaryTask due to not found")
            defaultModelForAuxiliaryTask = ""
        }

        if !defaultModelForAuxiliaryVisualTask.isEmpty {
            let localModelSatisfied = localModel(identifier: defaultModelForAuxiliaryVisualTask)?.capabilities.contains(.visual) ?? false
            let cloudModelSatisfied = cloudModel(identifier: defaultModelForAuxiliaryVisualTask)?.capabilities.contains(.visual) ?? false
            // Apple Intelligence does not support visual capabilities
            if !localModelSatisfied, !cloudModelSatisfied {
                Logger.model.debugFile("reset defaultModelForAuxiliaryVisualTask due to not found")
                defaultModelForAuxiliaryVisualTask = ""
            }
        }
    }

    func modelName(identifier: ModelIdentifier?) -> String {
        guard let identifier else { return "-" }
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            return AppleIntelligenceModel.shared.modelDisplayName
        }
        return cloudModel(identifier: identifier)?.modelFullName
            ?? localModel(identifier: identifier)?.model_identifier
            ?? "-"
    }

    func modelCapabilities(identifier: ModelIdentifier) -> Set<ModelCapabilities> {
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            // no endpoint
            return [.tool]
        }
        if let cloudModel = cloudModel(identifier: identifier) {
            return cloudModel.capabilities
        }
        if let localModel = localModel(identifier: identifier) {
            return localModel.capabilities
        }
        return []
    }

    func modelContextLength(identifier: ModelIdentifier) -> Int {
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            // Apple Intelligence: context length is not public, use a safe default
            return 8192
        }
        if let cloudModel = cloudModel(identifier: identifier) {
            return cloudModel.context.rawValue
        }
        if let localModel = localModel(identifier: identifier) {
            return localModel.context.rawValue
        }
        return 8192
    }

    static let temperaturePresets: [(title: String.LocalizationValue, value: Double, icon: String)] = [
        ("Disabled @ -1", -1.0, "gear"),
        ("Freezing @ 0.0", 0.0, "snowflake"),
        ("Precise @ 0.25", 0.25, "thermometer.low"),
        ("Stable @ 0.5", 0.5, "thermometer.low"),
        ("Humankind @ 0.75", 0.75, "thermometer.medium"),
        ("Creative @ 1.0", 1.0, "thermometer.medium"),
        ("Imaginative @ 1.5", 1.5, "thermometer.high"),
        ("Magical @ 2.0", 2.0, "thermometer.high"),
    ]

    func importModels(at urls: [URL], controller: UIViewController) {
        Indicator.progress(
            title: "Importing Model",
            controller: controller,
        ) { completionHandler in
            assert(!Thread.isMainThread)
            var success: [String] = []
            var errors: [String] = []
            for url in urls {
                if url.pathExtension.lowercased() == "zip" {
                    let result = ModelManager.shared.unpackAndImport(modelAt: url)
                    switch result {
                    case let .success(model):
                        success.append(model.model_identifier)
                    case let .failure(error):
                        errors.append(error.localizedDescription)
                    }
                    continue
                }
                if url.pathExtension.lowercased() == "plist" || url.pathExtension.lowercased() == "fdmodel" {
                    do {
                        let model = try ModelManager.shared.importCloudModel(at: url)
                        success.append(model.model_identifier)
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                    continue
                }
                errors.append(url.lastPathComponent)
            }
            if let error = errors.first {
                throw NSError(domain: "ModelImport", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            let count = success.count
            await completionHandler {
                let message = String(
                    format: String(localized: "Imported %d Models"),
                    count,
                )
                Indicator.present(title: "\(message)")
            }
        }
    }

    func dumpEligibleModelsToAppGroup() {
        let cloudModelsGroupSharingDir = AppGroup.sharedCloudModelsURL
        guard let cloudModelsGroupSharingDir else {
            Logger.model.errorFile("unable to determine app group location, skipping model sync")
            return
        }
        Logger.model.infoFile("syncing eligible model configurations to \(cloudModelsGroupSharingDir)")

        // due to limitations from appex
        // only cloud models are eligible for sharing via app group
        // and to be used in translation and keyboards
        if FileManager.default.fileExists(atPath: cloudModelsGroupSharingDir.path) {
            try? FileManager.default.removeItem(at: cloudModelsGroupSharingDir)
        }
        try? FileManager.default.createDirectory(at: cloudModelsGroupSharingDir, withIntermediateDirectories: true)
        lazy var encoder = PropertyListEncoder()
        for model in cloudModels.value {
            guard let data = try? encoder.encode(model) else {
                assertionFailure()
                continue
            }
            let url = cloudModelsGroupSharingDir
                .appendingPathComponent(model.id)
                .appendingPathExtension("plist")
            do {
                try data.write(to: url)
                Logger.model.infoFile("successfully write to \(url.path)")
            } catch {
                Logger.model.errorFile("unable to write on \(url.path) with error \(error.localizedDescription)")
            }
        }
    }
}

extension ModelManager {
    func responseFormat(for identifier: ModelIdentifier) -> CloudModel.ResponseFormat {
        cloudModel(identifier: identifier)?.response_format ?? .default
    }

    func updateResponseFormat(
        for identifier: ModelIdentifier,
        to newFormat: CloudModel.ResponseFormat,
    ) {
        editCloudModel(identifier: identifier) { model in
            model.update(\.response_format, to: newFormat)
        }
    }
}

extension ModelManager.ModelIdentifier {
    static var defaultModelForAuxiliaryTaskWillUseCurrentChatModel: Bool {
        get { ModelManager.shared.defaultModelForAuxiliaryTaskWillUseCurrentChatModel }
        set { ModelManager.shared.defaultModelForAuxiliaryTaskWillUseCurrentChatModel = newValue }
    }

    static var defaultModelForConversation: Self {
        get { ModelManager.shared.defaultModelForConversation }
        set { ModelManager.shared.defaultModelForConversation = newValue }
    }

    static var defaultModelForAuxiliaryTask: Self {
        get {
            if defaultModelForAuxiliaryTaskWillUseCurrentChatModel {
                ModelManager.shared.defaultModelForConversation
            } else {
                ModelManager.shared.defaultModelForAuxiliaryTask
            }
        }
        set { ModelManager.shared.defaultModelForAuxiliaryTask = newValue }
    }

    /// Returns the stored auxiliary model identifier, ignoring the "use chat model" setting
    static var storedAuxiliaryTaskModel: Self {
        ModelManager.shared.defaultModelForAuxiliaryTask
    }

    static var defaultModelForAuxiliaryVisualTask: Self {
        get { ModelManager.shared.defaultModelForAuxiliaryVisualTask }
        set { ModelManager.shared.defaultModelForAuxiliaryVisualTask = newValue }
    }
}
