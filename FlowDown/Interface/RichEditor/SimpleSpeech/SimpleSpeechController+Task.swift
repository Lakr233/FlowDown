//
//  SimpleSpeechController+Task.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/18/25.
//

import AVFAudio
import Speech
import UIKit

extension SimpleSpeechController {
    @objc func stopTranscriptButton() {
        doneButton.isEnabled = false
        doneButton.setTitle(NSLocalizedString("Transcript Stopped", comment: ""), for: .normal)
        stopTranscript()
        var text = textView.text ?? ""
        if text.hasSuffix(placeholderText) {
            text.removeLast(placeholderText.count)
        }
        callback(text)
        dismiss(animated: true)
    }

    func startTranscript() async {
        do {
            guard try await startTranscriptEx() else { return }
            doneButton.doWithAnimation { [self] in
                doneButton.isEnabled = true
            }
            doneButton.setTitle(NSLocalizedString("Stop Transcript", comment: ""), for: .normal)
        } catch {
            onErrorCallback(error)
            stopTranscript()
            dismiss(animated: true)
        }
    }

    func stopTranscript() {
        for item in sessionItems {
            if let task = item as? SFSpeechRecognitionTask {
                task.cancel()
            }
            if let engine = item as? AVAudioEngine {
                // the session cannot be deactivated while the engine is still running
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }
        }
        sessionItems.removeAll()
        // Give the shared session back: stop ducking other apps and restore the
        // playback category that stream audio feedback relies on.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        SoundEffectPlayer.shared.updateMode()
    }

    /// Returns false when the sheet was closed while a permission prompt was up.
    private func startTranscriptEx() async throws -> Bool {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw NSError(domain: "SpeechRecognizer", code: 0, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Speech recognizer is not authorized.", comment: ""),
            ])
        }

        let micPermissionGranted: Bool
        if #available(iOS 17, macCatalyst 17, *) {
            micPermissionGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micPermissionGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { @Sendable granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard micPermissionGranted else {
            throw NSError(domain: "SpeechRecognizer", code: 0, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Microphone is not authorized.", comment: ""),
            ])
        }

        guard presentingViewController != nil, !isBeingDismissed else { return false }

        // appLang if non‐English, otherwise Locale.preferredLanguages.first
        let appLang = Bundle.main.preferredLocalizations.first ?? "en"
        let preferred = (appLang != "en") ? appLang
            : Locale.preferredLanguages.first ?? "en"
        let localeID = preferred.replacingOccurrences(of: "_", with: "-")
        let speechLocale = Locale(identifier: localeID)

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        guard let speechRecognizer = SFSpeechRecognizer(locale: speechLocale) else {
            throw NSError(domain: "SpeechRecognizer", code: 0, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Speech recognizer is not available.", comment: ""),
            ])
        }

        let recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, _ in
            guard let result else { return }
            self.textView.text = result.bestTranscription.formattedString
            self.textView.doWithAnimation {
                self.textView.contentOffset = .init(
                    x: 0,
                    y: max(0, self.textView.contentSize.height - self.textView.bounds.size.height),
                )
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        sessionItems.append(audioEngine)
        sessionItems.append(inputNode)
        sessionItems.append(recognitionTask)
        return true
    }
}
