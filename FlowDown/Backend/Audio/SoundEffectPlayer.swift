//
//  SoundEffectPlayer.swift
//  FlowDown
//
//  Created by AI on 1/6/26.
//

import AVFoundation
import ConfigurableKit
import Foundation

@MainActor
class SoundEffectPlayer: NSObject {
    static let shared = SoundEffectPlayer()

    static let customAudioDirectoryName = "Audio"
    static let customAudioFileName = "streaming_audio_effect.m4a"

    private var audioPlayers: [AVAudioPlayer] = []
    private var customPlayer: AVAudioPlayer?
    private var currentMode: StreamAudioEffectSetting = .off
    private var timer: Timer?
    private var tik: Int = 0
    private var tok: Int = 0

    override private init() {
        super.init()

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timerTick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        updateMode()
        Task.detached { await self.preloadAudioFiles() }
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    private nonisolated func preloadAudioFiles() async {
        var players: [AVAudioPlayer] = []
        for i in 0 ... 9 {
            guard let url = Bundle.main.url(
                forResource: "dial_tune_\(i)",
                withExtension: "m4a",
                subdirectory: "DialTune",
            ) else {
                assertionFailure()
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players.append(player)
            } catch {
                logger.error("Failed to load audio file dial_tune_\(i): \(error)")
                assertionFailure()
            }
        }

        let list = players
        await MainActor.run { self.audioPlayers = list }
        await loadCustomAudio()
    }

    private nonisolated func loadCustomAudio() async {
        guard let url = await Self.customAudioURL(),
              FileManager.default.fileExists(atPath: url.path)
        else {
            await MainActor.run { self.customPlayer = nil }
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            await MainActor.run { self.customPlayer = player }
        } catch {
            logger.error("failed to load custom sound effect: \(error)")
            await MainActor.run { self.customPlayer = nil }
        }
    }

    func reloadCustomAudio() {
        Task.detached { [weak self] in
            await self?.loadCustomAudio()
        }
    }

    func updateMode() {
        currentMode = StreamAudioEffectSetting.configuredMode()

        let isActivated = currentMode != .off
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(isActivated)
            logger.info("setting audio session to \(isActivated)")
        } catch {
            logger.error("failed to set audio session mode \(error.localizedDescription)")
        }
    }

    func play() {
        guard currentMode != .off else { return }
        tik += 1
    }

    private func timerTick() {
        let player: AVAudioPlayer?
        if currentMode == .custom {
            player = customPlayer
        } else if let audioIndex = currentMode.audioIndex,
                  audioIndex >= 0,
                  audioIndex < audioPlayers.count
        {
            player = audioPlayers[audioIndex]
        } else {
            player = nil
        }

        guard let player, tik > tok else { return }
        tok = tik
        player.currentTime = 0
        player.play()
    }
}

extension SoundEffectPlayer {
    static func customAudioDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(customAudioDirectoryName, isDirectory: true)
    }

    static func customAudioURL() -> URL? {
        customAudioDirectory()?
            .appendingPathComponent(customAudioFileName)
    }

    static func ensureCustomAudioDirectory() throws -> URL {
        enum AudioFileError: LocalizedError {
            case missingDocumentsDirectory // won't happen
        }

        guard let directory = customAudioDirectory() else {
            throw AudioFileError.missingDocumentsDirectory
        }
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        }
        return directory
    }
}
