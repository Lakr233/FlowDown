//
//  TranslationProviderView+Footer.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import ExtensionKit
@preconcurrency import Storage
import SwiftUI
import TranslationUIProvider

private extension CloudModel {
    var buttonName: String {
        if !name.isEmpty {
            return name
        }
        return model_identifier
    }
}

extension TranslationProviderView {
    private var controlText: String {
        "\(selectedModel?.buttonName ?? "") - \(targetLanguage)"
    }

    var footer: some View {
        VStack(spacing: 8) {
            if let translationError = translationModel.translationError {
                Text(translationError.localizedDescription)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .transition(.opacity)
            }
            HStack {
                buttons
            }
            .disabled(!canTranslate)
            .opacity(canTranslate ? 1.0 : 0.25)
            Text(controlText)
                .opacity(0.5)
                .contentTransition(.numericText())
                .font(.caption)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Menu {
            ForEach(models) { model in
                Toggle(model.buttonName, isOn: .init(get: {
                    selectedModelIdentifier == model.id
                }, set: { newValue in
                    if newValue {
                        selectedModelIdentifier = model.id
                        translate()
                    }
                }))
            }
        } label: {
            IconButtonContainer(icon: "person", foregroundColor: .primary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        Menu {
            ForEach(CommonTranslationLanguage.allCases) { language in
                Button(language.title) {
                    selectedLanguageHint = language.localizedDescription
                    translate()
                }
            }
        } label: {
            IconButtonContainer(icon: "globe", foregroundColor: .primary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        Button {
            translate()
        } label: {
            IconButtonContainer(icon: "arrow.clockwise", foregroundColor: .primary)
        }
        .buttonStyle(.plain)
        Button {
            let text = translationModel.copyableResult
            if !text.isEmpty {
                UIPasteboard.general.string = text
            }
            context.finish(translation: nil)
        } label: {
            IconButtonContainer(icon: "doc.on.doc.fill", foregroundColor: .accent)
        }
        .buttonStyle(.plain)
    }
}
