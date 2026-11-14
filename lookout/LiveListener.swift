import Foundation
import Speech
import AVFoundation

/// Streams the microphone into Apple's speech recognizer and reports the running transcript.
/// This is the stand-in for the band's microphone: replace it when the band SDK is available.
@MainActor
final class LiveListener {

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var interruptionTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?

    private var onText: ((String) -> Void)?
    private var onError: ((String) -> Void)?

    private var running = false
    private var hasTapInstalled = false
    private var generation = 0     // ignores callbacks from a recognition task we already replaced
    private var committed = ""     // text from finished segments
    private var latest = ""        // text from the current segment

    func start(onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        stop()
        self.onText = onText
        self.onError = onError
        committed = ""
        latest = ""
        running = true

        observeInterruptions()

        Task {
            guard await Self.speechAuthorized() else {
                fail("Speech recognition is turned off for Lookout. Enable it in Settings.")
                return
            }
            guard await AVAudioApplication.requestRecordPermission() else {
                fail("Microphone access is turned off for Lookout. Enable it in Settings.")
                return
            }
            guard running else { return }
            do {
                try begin()
            } catch {
                fail("Couldn't start listening: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        running = false
        restartTask?.cancel()
        restartTask = nil
        interruptionTask?.cancel()
        interruptionTask = nil
        teardown(deactivateSession: true)
    }

    // MARK: - Private

    private func begin() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ListenerError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true   // audio stays on the phone
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw ListenerError.noMicrophone }
        if hasTapInstalled {
            input.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        if #available(iOS 27.0, *) {
            try input.installAudioTap(
                onBus: 0,
                bufferSize: 4096,
                format: format,
                tapProvider: Self.tapProvider(for: request)
            )
        } else {
            Self.installLegacyTap(on: input, format: format, request: request)
        }
        hasTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()

        generation += 1
        let gen = generation
        task = Self.recognize(recognizer, request) { [weak self] text, finished in
            Task { @MainActor [weak self] in
                self?.handle(text: text, finished: finished, gen: gen)
            }
        }
    }

    private func handle(text: String?, finished: Bool, gen: Int) {
        guard running, gen == generation else { return }

        if let text, !text.isEmpty {
            latest = text
            onText?(joined)
        }

        guard finished else { return }

        // The recognizer ends a segment after a pause or timeout. Keep what we have and start a new one.
        if latest.isEmpty && committed.isEmpty {
            fail("Listening stopped because no speech was heard. Tap Listen live to resume.")
            return
        }
        committed = joined
        latest = ""
        teardown(deactivateSession: false)

        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled, self.running else { return }
            do {
                try self.begin()
            } catch {
                self.fail("Listening stopped: \(error.localizedDescription)")
            }
        }
    }

    private var joined: String {
        [committed, latest].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func observeInterruptions() {
        interruptionTask?.cancel()
        interruptionTask = Task { [weak self] in
            if #available(iOS 27.0, *) {
                let notifications = NotificationCenter.default.notifications(
                    named: AVAudioSession.didBecomeInactiveNotification
                )
                for await _ in notifications {
                    guard let self, self.running, self.audioEngine.isRunning else { continue }
                    self.fail("Listening was interrupted by another audio session or phone call.")
                    return
                }
            } else {
                let notifications = NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification
                )
                for await _ in notifications {
                    guard let self, self.running, self.audioEngine.isRunning else { continue }
                    self.fail("Listening was interrupted by another audio session or phone call.")
                    return
                }
            }
        }
    }

    private func teardown(deactivateSession: Bool) {
        generation += 1
        if audioEngine.isRunning { audioEngine.stop() }
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func fail(_ message: String) {
        running = false
        restartTask?.cancel()
        restartTask = nil
        interruptionTask?.cancel()
        interruptionTask = nil
        teardown(deactivateSession: true)
        onError?(message)
    }

    // These run on audio and speech threads, so they must stay off the main actor.

    nonisolated private static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    @available(iOS 27.0, *)
    nonisolated private static func tapProvider(
        for request: SFSpeechAudioBufferRecognitionRequest
    ) -> @Sendable (AVReadOnlyAudioPCMBuffer, AVAudioTime) -> Void {
        return { readOnlyBuffer, _ in
            let pcmBuffer = AVAudioPCMBuffer(copying: readOnlyBuffer)
            request.append(pcmBuffer)
        }
    }

    @available(iOS, deprecated: 27.0)
    nonisolated private static func installLegacyTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(
        _ recognizer: SFSpeechRecognizer,
        _ request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            update(text, finished)
        }
    }
}

enum ListenerError: LocalizedError {
    case recognizerUnavailable
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognition isn't available right now."
        case .noMicrophone: return "No microphone input was found."
        }
    }
}
