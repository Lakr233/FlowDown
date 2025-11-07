import AppIntents
import Foundation

enum ShortcutsEntities {
    struct ModelEntity: AppEntity, Identifiable {
        static var typeDisplayRepresentation: TypeDisplayRepresentation {
            .init(name: LocalizedStringResource("Model"))
        }

        static var defaultQuery: ShortcutsEntities.ModelQuery { .init() }

        enum Source: String, Hashable {
            case local
            case cloud
            case apple

            var localizedDescription: LocalizedStringResource {
                switch self {
                case .local:
                    LocalizedStringResource("Local")
                case .cloud:
                    LocalizedStringResource("Cloud")
                case .apple:
                    LocalizedStringResource("Apple Intelligence")
                }
            }
        }

        let id: ModelManager.ModelIdentifier
        let displayName: String
        let source: Source
        let searchKeywords: [String]

        var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: displayName),
                subtitle: source.localizedDescription
            )
        }

        init(
            id: ModelManager.ModelIdentifier,
            displayName: String,
            source: Source,
            searchKeywords: [String] = []
        ) {
            self.id = id
            self.displayName = displayName
            self.source = source
            self.searchKeywords = searchKeywords
        }

        func matches(_ term: String) -> Bool {
            let lowercasedTerm = term.lowercased()
            if displayName.lowercased().contains(lowercasedTerm) { return true }
            if id.lowercased().contains(lowercasedTerm) { return true }
            if searchKeywords.contains(where: { $0.contains(lowercasedTerm) }) { return true }
            return false
        }
    }

    struct ModelQuery: EntityQuery {
        func entities(for identifiers: [ModelEntity.ID]) async throws -> [ModelEntity] {
            let available = await loadEntities()
            let identifierSet = Set(identifiers)
            return available.filter { identifierSet.contains($0.id) }
        }

        func suggestedEntities() async throws -> [ModelEntity] {
            let available = await loadEntities()
            return Array(available.prefix(6))
        }

        func entities(matching string: String) async throws -> [ModelEntity] {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return try await allEntities() }

            return await loadEntities().filter { entity in
                entity.matches(trimmed)
            }
        }

        func allEntities() async throws -> [ModelEntity] {
            await loadEntities()
        }

        private func loadEntities() async -> [ModelEntity] {
            await MainActor.run {
                let manager = ModelManager.shared
                var entities: [ModelManager.ModelIdentifier: ModelEntity] = [:]

                func normalizedKeywords(_ keywords: [String]) -> [String] {
                    keywords
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty }
                }

                for model in manager.localModels.value {
                    let identifier = model.id
                    guard !identifier.isEmpty else { continue }
                    let name = manager.modelName(identifier: identifier)
                    let keywords = normalizedKeywords([
                        model.model_identifier,
                        identifier,
                        name,
                    ])
                    entities[identifier] = ModelEntity(
                        id: identifier,
                        displayName: name,
                        source: .local,
                        searchKeywords: keywords
                    )
                }

                for model in manager.cloudModels.value {
                    let identifier = model.id
                    guard !identifier.isEmpty else { continue }
                    if entities[identifier] != nil { continue }
                    let name = manager.modelName(identifier: identifier)
                    var keywords = [
                        model.model_identifier,
                        identifier,
                        name,
                        model.endpoint,
                    ]
                    if !model.name.isEmpty {
                        keywords.append(model.name)
                    }
                    let normalized = normalizedKeywords(keywords)
                    entities[identifier] = ModelEntity(
                        id: identifier,
                        displayName: name,
                        source: .cloud,
                        searchKeywords: normalized
                    )
                }

                if #available(iOS 26.0, macCatalyst 26.0, *), AppleIntelligenceModel.shared.isAvailable {
                    let identifier = AppleIntelligenceModel.shared.modelIdentifier
                    entities[identifier] = ModelEntity(
                        id: identifier,
                        displayName: AppleIntelligenceModel.shared.modelDisplayName,
                        source: .apple,
                        searchKeywords: normalizedKeywords([
                            AppleIntelligenceModel.shared.modelDisplayName,
                            identifier,
                        ])
                    )
                }

                return entities.values
                    .sorted { lhs, rhs in
                        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
            }
        }
    }
}
