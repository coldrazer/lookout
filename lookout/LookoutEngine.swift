import SwiftUI
import Observation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct TranscriptLine: Identifiable {
    let id = UUID()
    var speaker: String
    var text: String
}

/// The Lookout loop: listen -> score -> interrupt -> escalate.
@Observable
@MainActor
final class LookoutEngine {

    enum Mode {
        case idle, demoCall, listening, alerted
    }

    var mode: Mode = .idle
    var lines: [TranscriptLine] = []
    var assessment = ScamAssessment()
    var errorText: String?

    /// Risk at or above this fires the alert.
    let threshold = 0.8

    @ObservationIgnored private let scorer: ScamScoring = KeywordScamScorer()
    @ObservationIgnored private let voice = AVSpeechSynthesizer()
    @ObservationIgnored private let speechCoordinator = SpeechCoordinator()
    @ObservationIgnored private let listener = LiveListener()
    @ObservationIgnored private var demoTask: Task<Void, Never>?

    static let demoScript = [
        "Grandma? It's me. I'm in trouble and I need your help. Please don't tell Mom.",
        "I was in an accident.",
        "I need two thousand dollars in gift cards, right now.",
        "Stay on the phone and don't hang up."
    ]

    init() {
        voice.delegate = speechCoordinator
    }

    // Names come from the Settings sheet (stored in UserDefaults by @AppStorage).
    var wearerName: String { stored("wearerName", fallback: "Rosa") }
    var caregiverName: String { stored("caregiverName", fallback: "Maria") }

    var warning: String? {
        guard mode == .alerted else { return nil }
        return warningMessage(wearer: wearerName, caregiver: caregiverName)
    }

    var caregiverMessage: String {
        caregiverMessage(wearer: wearerName)
    }

    func warningMessage(wearer: String, caregiver: String) -> String {
        let resolvedWearer = Self.nonEmpty(wearer, fallback: "Rosa")
        let resolvedCaregiver = Self.nonEmpty(caregiver, fallback: "Maria")
        return "\(resolvedWearer), this sounds like a scam. Hang up and call \(resolvedCaregiver)."
    }

    func caregiverMessage(wearer: String) -> String {
        let resolvedWearer = Self.nonEmpty(wearer, fallback: "Rosa")
        let signs = assessment.signals.map { $0.label.lowercased() }.joined(separator: ", ")
        return "Lookout: \(resolvedWearer) got a likely scam call (risk \(assessment.percent)%). "
            + "Signs: \(signs). Lookout told \(resolvedWearer) to hang up and call you."
    }

    // MARK: - Controls

    /// Plays a scripted scam call out loud and scores it line by line. Works in the Simulator.
    func runDemoCall() {
        reset()
        mode = .demoCall
        preparePlayback()

        demoTask = Task { [weak self] in
            for line in Self.demoScript {
                guard let self, !Task.isCancelled, self.mode == .demoCall else { return }
                self.lines.append(TranscriptLine(speaker: "Caller", text: line))
                await self.sayAndWait(line, asCaller: true)

                guard !Task.isCancelled, self.mode == .demoCall else { return }
                self.rescore()
                guard self.mode == .demoCall else { return }

                try? await Task.sleep(for: .milliseconds(350))
            }
            if let self, self.mode == .demoCall {
                self.mode = .idle
                self.deactivatePlaybackSession()
            }
        }
    }

    /// Listens through the microphone. Put a call on speaker, or read the scam lines aloud.
    func startListening() {
        reset()
        mode = .listening
        lines = [TranscriptLine(speaker: "Live", text: "")]

        listener.start(
            onText: { [weak self] text in
                guard let self, self.mode == .listening, !self.lines.isEmpty else { return }
                self.lines[0].text = text
                self.rescore()
            },
            onError: { [weak self] message in
                guard let self else { return }
                self.errorText = message
                if self.mode == .listening { self.mode = .idle }
            }
        )
    }

    func stop() {
        demoTask?.cancel()
        demoTask = nil
        listener.stop()
        speechCoordinator.cancelPending()
        voice.stopSpeaking(at: .immediate)
        if mode != .alerted {
            mode = .idle
            deactivatePlaybackSession()
        }
    }

    func reset() {
        demoTask?.cancel()
        demoTask = nil
        listener.stop()
        speechCoordinator.cancelPending()
        voice.stopSpeaking(at: .immediate)
        mode = .idle
        lines = []
        assessment = ScamAssessment()
        errorText = nil
        deactivatePlaybackSession()
    }

    // MARK: - Scoring and alert

    private func rescore() {
        let transcript = lines.map(\.text).joined(separator: " ")
        assessment = scorer.assess(transcript)
        if assessment.risk >= threshold && mode != .alerted {
            fireAlert()
        }
    }

    private func fireAlert() {
        demoTask?.cancel()
        demoTask = nil
        listener.stop()
        speechCoordinator.cancelPending()
        voice.stopSpeaking(at: .immediate)
        mode = .alerted

        let message = warningMessage(wearer: wearerName, caregiver: caregiverName)

        // Phone haptics and speaker stand in for the band. Swap these two calls for the band SDK.
        preparePlayback()
        buzz()
        say(message, asCaller: false)
    }

    private func buzz() {
        #if os(iOS)
        Task {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            for _ in 0..<3 {
                generator.notificationOccurred(.error)
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        #endif
    }

    private func say(_ text: String, asCaller: Bool) {
        let utterance = makeUtterance(text, asCaller: asCaller)
        voice.speak(utterance)
    }

    private func sayAndWait(_ text: String, asCaller: Bool) async {
        let utterance = makeUtterance(text, asCaller: asCaller)
        let fallbackSeconds = 1.2 + Double(text.count) * 0.075
        await speechCoordinator.speak(utterance, using: voice, timeoutSeconds: fallbackSeconds)
    }

    private func makeUtterance(_ text: String, asCaller: Bool) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = asCaller ? 0.52 : 0.46
        utterance.pitchMultiplier = asCaller ? 1.25 : 0.95
        return utterance
    }

    private func preparePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivatePlaybackSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stored(_ key: String, fallback: String) -> String {
        Self.nonEmpty(UserDefaults.standard.string(forKey: key) ?? "", fallback: fallback)
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

/// Bridges `AVSpeechSynthesizerDelegate` callbacks into async/await with a safe fallback timeout.
@MainActor
private final class SpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func speak(
        _ utterance: AVSpeechUtterance,
        using synthesizer: AVSpeechSynthesizer,
        timeoutSeconds: Double
    ) async {
        cancelPending()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            synthesizer.speak(utterance)

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return }
                self?.finishPending()
            }
        }
    }

    func cancelPending() {
        finishPending()
    }

    private func finishPending() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation {
            self.continuation = nil
            continuation.resume()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finishPending()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finishPending()
        }
    }
}
