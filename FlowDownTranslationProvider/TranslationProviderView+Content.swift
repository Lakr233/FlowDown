//
//  TranslationProviderView+Content.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import SwiftUI

extension TranslationProviderView {
    @ViewBuilder
    var content: some View {
        if canTranslate {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !translationModel.translationSegmentedResult.isEmpty {
                        ForEach(translationModel.translationSegmentedResult) { segment in
                            TranslateSegmentView(segment: segment)
                        }
                        .transition(.opacity)
                    } else if !translationModel.translationPlainResult.isEmpty {
                        Text(translationModel.translationPlainResult)
                            .textSelection(.enabled)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.numericText())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !translationModel.isTranslating {
                        Text("(Empty Content)")
                            .opacity(0.5)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    if translationModel.isTranslating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                if inputText.isEmpty {
                    Text("Please select text to translate")
                } else if models.isEmpty {
                    Text("No cloud models available for translation. Please add cloud models in FlowDown app.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
