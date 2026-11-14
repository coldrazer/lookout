import Foundation

/// One kind of scam marker, with the phrases that trigger it.
struct ScamSignal: Identifiable, Hashable {
    let id: String
    let label: String
    let weight: Double      // 0...1, how strongly this marker points to a scam
    let phrases: [String]   // lowercase
}

struct ScamAssessment {
    var risk: Double = 0
    var signals: [ScamSignal] = []

    var percent: Int { Int((min(max(risk, 0), 1) * 100).rounded()) }

    var reason: String {
        signals.isEmpty ? "No scam markers yet" : signals.map(\.label).joined(separator: ", ")
    }
}

/// Swap in a model-backed scorer later by conforming to this.
protocol ScamScoring {
    func assess(_ transcript: String) -> ScamAssessment
}

/// Offline keyword scorer. No network, no API key.
/// Risk combines the distinct markers heard so far: 1 - product(1 - weight).
struct KeywordScamScorer: ScamScoring {

    static let signals: [ScamSignal] = [
        ScamSignal(id: "payment", label: "Gift cards or untraceable payment", weight: 0.45,
                   phrases: ["gift card", "gift cards", "wire transfer", "wire the money", "western union",
                             "moneygram", "bitcoin", "crypto", "zelle", "cash app", "venmo", "prepaid card",
                             "prepaid cards"]),
        ScamSignal(id: "credentials", label: "Asks for codes or account access", weight: 0.40,
                   phrases: ["verification code", "security code", "one time code", "password", "pin number",
                             "social security number", "remote access", "account number", "routing number"]),
        ScamSignal(id: "stay", label: "Keeps you on the line", weight: 0.35,
                   phrases: ["don't hang up", "do not hang up", "stay on the phone", "stay on the line"]),
        ScamSignal(id: "secrecy", label: "Secrecy", weight: 0.30,
                   phrases: ["don't tell", "do not tell", "keep this between us", "keep it a secret",
                             "nobody can know", "no one can know"]),
        ScamSignal(id: "emergency", label: "Family emergency", weight: 0.25,
                   phrases: ["accident", "in trouble", "in jail", "arrested", "hospital", "bail", "lawyer"]),
        ScamSignal(id: "urgency", label: "Urgency", weight: 0.25,
                   phrases: ["right now", "right away", "immediately", "as soon as possible", "hurry",
                             "before it's too late", "today only"]),
        ScamSignal(id: "money", label: "Asks for money", weight: 0.25,
                   phrases: ["dollars", "$", "send money", "send me money", "thousand", "payment", "pay the"]),
        ScamSignal(id: "impersonation", label: "Claims to be family or an official", weight: 0.20,
                   phrases: ["grandma", "grandpa", "it's me", "your grandson", "your granddaughter",
                             "your bank", "the irs", "social security administration", "fraud department",
                             "tech support", "microsoft", "medicare"])
    ]

    func assess(_ transcript: String) -> ScamAssessment {
        let normalized = Self.normalize(transcript)
        guard !normalized.isEmpty else { return ScamAssessment() }

        var hit: [ScamSignal] = []
        var safe = 1.0
        for signal in Self.signals where Self.matches(signal: signal, in: normalized) {
            hit.append(signal)
            safe *= (1 - signal.weight)
        }
        let rawRisk = min(max(1 - safe, 0), 1)
        return ScamAssessment(risk: rawRisk, signals: hit)
    }

    // MARK: - Word-boundary phrase matching

    /// Normalizes curly apostrophes and collapses whitespace while preserving word boundaries.
    private static func normalize(_ transcript: String) -> String {
        transcript
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    private static func matches(signal: ScamSignal, in text: String) -> Bool {
        signal.phrases.contains { phrase in
            containsPhrase(phrase, in: text)
        }
    }

    /// Matches a phrase on word boundaries so substrings like "available" do not trigger "bail".
    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        if phrase == "$" {
            return text.contains("$")
        }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = "(?:^|\\b)\(escaped)(?:\\b|$)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
