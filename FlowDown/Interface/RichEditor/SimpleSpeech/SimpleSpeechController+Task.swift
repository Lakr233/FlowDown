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

    func startTranscript() {
        do {
            try startTranscriptEx()
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
        }
        sessionItems.removeAll()
    }

    private func startTranscriptEx() throws {
        SFSpeechRecognizer.requestAuthorization { _ in }
        if #available(iOS 17, macCatalyst 17, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: { _ in })
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw NSError(domain: "SpeechRecognizer", code: 0, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Speech recognizer is not authorized.", comment: ""),
            ])
        }

        let micPermissionGranted: Bool = if #available(iOS 17, macCatalyst 17, *) {
            AVAudioApplication.shared.recordPermission == .granted
        } else {
            AVAudioSession.sharedInstance().recordPermission == .granted
        }

        guard micPermissionGranted else {
            throw NSError(domain: "SpeechRecognizer", code: 0, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Microphone is not authorized.", comment: ""),
            ])
        }

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
    }
}
