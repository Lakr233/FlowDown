//
//  TranslationProviderView.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import ChatClientKit
import ExtensionKit
import Storage
import SwiftUI
import TranslationUIProvider

@MainActor
struct TranslationProviderView: View {
    @State var context: TranslationUIProviderContext
    @State var inputText: String

    let models: [CloudModel]
    @StateObject var translationModel = TranslationProviderModel()
    @AppStorage("wiki.qaq.fd.tp.selectedModelIdentifier")
    var selectedModelIdentifier: CloudModel.ID = ""
    @AppStorage("wiki.qaq.fd.tp.selectedLanguageHint")
    var selectedLanguageHint: String = ""
    @State var translateOnAppear = true

    var canTranslate: Bool {
        guard models.map(\.id).contains(selectedModelIdentifier),
              !inputText.isEmpty
        else { return false }
        return true
    }

    var model: CloudModel {
        models.first { $0.id == selectedModelIdentifier } ?? .init(deviceId: "")
    }

    var currentLocaleDescription: String {
        Locale.current.identifier
    }

    init(context c: TranslationUIProviderContext) {
        context = c
        models = scanModels()
        inputText = ""
    }

    @State var booting = true

    var body: some View {
        VStack {
            content
                .opacity(booting ? 0 : 1)
                .animation(.spring, value: booting)
            footer
        }
        .padding(.horizontal)
        .animation(.spring, value: translationModel.translationError?.localizedDescription)
        .animation(.spring, value: translationModel.translationReasoning)
        .animation(.spring, value: translationModel.translationPlainResult)
        .animation(.spring, value: translationModel.translationSegmentedResult)
        .animation(.spring, value: translationModel.isTranslating ? 1 : 0)
        .animation(.spring, value: selectedModelIdentifier)
        .animation(.spring, value: selectedLanguageHint)
        .onAppear {
            guard translateOnAppear else { return }
            translateOnAppear = false
            if let input = context.inputText {
                var candidate = NSAttributedString(input)
                    .string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                while candidate.contains("\n\n") {
                    candidate = candidate.replacingOccurrences(of: "\n\n", with: "\n")
                }
                inputText = candidate
            }
            if selectedModelIdentifier == "" || !models.map(\.id).contains(selectedModelIdentifier) {
                selectedModelIdentifier = models.first?.id ?? ""
            }
            translate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                booting = false
            }
        }
    }

    func translate() {
        guard canTranslate else { return }
        let targetLanguage = selectedLanguageHint.isEmpty ? currentLocaleDescription : selectedLanguageHint
        translationModel.translate(
            inputText: inputText,
            model: model,
            language: targetLanguage,
        )
    }
}
