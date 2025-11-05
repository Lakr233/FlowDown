//
//  ConversationSession+Images.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/20/25.
//

import ChatClientKit
import Combine
import Foundation
import SwifterSwift
import UIKit
import Vision

private let languageIdentifiers: [String] = {
    var languageIdentifiers = Locale.LanguageCode.isoLanguageCodes.map(\.identifier)
    let englishIdentifier: String = Locale.LanguageCode.english.identifier
    let chineseIdentifier: String = Locale.LanguageCode.chinese.identifier
    if !languageIdentifiers.contains(englishIdentifier) {
        languageIdentifiers.append(englishIdentifier)
    }
    if !languageIdentifiers.contains(chineseIdentifier) {
        languageIdentifiers.append(chineseIdentifier)
    }
    return languageIdentifiers
}()

extension ConversationSession {
    func processImageToText(
        image: UIImage,
        _ currentMessageListView: MessageListView

    ) async throws -> String {
        try checkCancellation()

        var messages: [ChatRequestBody.Message] = [
            .system(content: .text(String(localized:
                """
                Please provide a detailed description of the following image. The description should include the main elements in the image, the scene, colors, objects, people, and any significant details. Aim to give comprehensive information to help understand the meaning or context of the image.

                1. What is the overall theme or setting of the image?
                2. Are there any specific objects, buildings, or natural landscapes in the image? If so, please describe them.
                3. Are there any people in the image? If yes, describe their appearance, expressions, actions, and their relation to other elements.
                4. How do the colors and lighting in the image appear? Are there any prominent colors or contrasts?
                5. What is in the foreground and background of the image? Are there any important details to note?
                6. Does the image convey any specific emotions or atmosphere? If so, describe the mood or feeling.
                7. Any other details that you find important or interesting, please include them.

                If you are unable to describe the image, you may output [Unable to Identify the image.].
                """
            ))),
        ]

        guard let base64 = image.pngBase64String(),
              let url = URL(string: "data:image/png;base64,\(base64)")
        else {
            assertionFailure()
            return String(localized: "Unable to decode image.")
        }

        messages.append(.user(content: .parts([.imageURL(url)])))
        messages.append(.user(content: .text(String(localized: "Please describe the image."))))

        var decision: ModelManager.ModelIdentifier?
        if decision == nil,
           let model = models.visualAuxiliary,
           ModelManager.shared.modelCapabilities(identifier: model).contains(.visual)
        { decision = model }
        guard let decision else { return "" }

        Logger.model.infoFile("describing image with model: \(ModelManager.shared.modelName(identifier: decision))")

        try checkCancellation()
        try await Task.sleep(for: .seconds(0.5)) // for animation

        var llmText = ""
        let message = appendNewMessage(role: .assistant)
        message.modelIdentifier = decision
        for try await resp in try await ModelManager.shared.streamingInfer(
            with: decision,
            input: messages
        ) {
            await requestUpdate(view: currentMessageListView)
            startThinking(for: message.objectId)
            llmText = resp.content
            message.update(\.reasoningContent, to: llmText)
            await requestUpdate(view: currentMessageListView)
        }

        if !message.reasoningContent.isEmpty {
            let document = String(localized: "I have recognized this image.")
            message.update(\.document, to: document)
        }

        let collapseAfterReasoningComplete = ModelManager.shared.collapseReasoningSectionWhenComplete
        if collapseAfterReasoningComplete {
            message.update(\.isThinkingFold, to: true)
        }
        stopThinking(for: message.objectId)
        await requestUpdate(view: currentMessageListView)
        await currentMessageListView.loading()

        llmText = llmText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if llmText.isEmpty {
            llmText = String(localized: "Unable to identify the image with tool model.")
        }

        var ans = ""
        ans += "[Image Description]\n\(llmText)\n"

        try checkCancellation()
        if let ocrAns = try? await executeOpticalCharacterRecognition(on: image), !ocrAns.isEmpty {
            ans += "[Image Optical Character Recognition Result]\n\(ocrAns)\n"
        }

        try checkCancellation()
        if let qrAns = executeQRCodeRecognition(on: image), !qrAns.isEmpty {
            ans += "[QRCode Recognition]\n\(qrAns)\n"
        }

        Logger.model.infoFile("describing image returns:\n\(ans)")
        return ans
    }

    // OCR
    private func executeOpticalCharacterRecognition(on image: UIImage) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: "")
                    return
                }

                let result: String = observations.map { observation in
                    observation.topCandidates(1).first?.string ?? ""
                }
                .joined(separator: "\n")
                cont.resume(returning: result)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languageIdentifiers
            request.usesLanguageCorrection = true
            // perform request
            guard let cgIamge = image.cgImage else {
                cont.resume(returning: "")
                return
            }
            let handler = VNImageRequestHandler(cgImage: cgIamge)
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    private func executeQRCodeRecognition(on image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            return nil
        }
        let features = detector.features(in: ciImage)
        let qrCodeFeatures = features.compactMap { $0 as? CIQRCodeFeature }
        guard let qrCode = qrCodeFeatures.first?.messageString else {
            return nil
        }
        return qrCode
    }
}
