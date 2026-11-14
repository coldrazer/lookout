import SwiftUI

struct ContentView: View {
    @State private var engine = LookoutEngine()
    @AppStorage("wearerName") private var wearerName = "Rosa"
    @AppStorage("caregiverName") private var caregiverName = "Maria"
    @AppStorage("caregiverPhone") private var caregiverPhone = ""
    @Environment(\.openURL) private var openURL
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if engine.mode == .alerted {
                        alertCard(
                            engine.warningMessage(wearer: wearerName, caregiver: caregiverName)
                        )
                    }
                    riskCard
                    transcriptCard
                    if let error = engine.errorText {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    controls
                }
                .padding()
                .animation(.easeOut(duration: 0.35), value: engine.assessment.risk)
                .animation(.easeOut(duration: 0.35), value: engine.mode)
            }
            .navigationTitle("Lookout")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("People")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Cards

    private func alertCard(_ warning: String) -> some View {
        let message = engine.caregiverMessage(wearer: wearerName)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Scam alert", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(warning)
                .font(.title3.weight(.semibold))

            Divider().overlay(.white.opacity(0.4))

            Text("Message for \(displayCaregiver)")
                .font(.caption.weight(.semibold))
                .opacity(0.85)
            Text(message)
                .font(.subheadline)

            HStack {
                Button {
                    if let url = smsURL(for: message) { openURL(url) }
                } label: {
                    Label("Text \(displayCaregiver)", systemImage: "message.fill")
                }
                .buttonStyle(.borderedProminent)
                // When disabled, switch to a translucent white look so the label stays legible on the red card.
                .tint(smsURL(for: message) == nil ? .white.opacity(0.25) : .white)
                .foregroundStyle(smsURL(for: message) == nil ? .white : .red)
                .disabled(smsURL(for: message) == nil)

                ShareLink(item: message) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            if smsURL(for: message) == nil {
                Text("Add a phone number under People to text from here.")
                    .font(.caption)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 20))
    }

    private var riskCard: some View {
        let clampedRisk = min(max(engine.assessment.risk, 0), 1)
        let thresholdPercent = Int((engine.threshold * 100).rounded())

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("SCAM RISK")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(engine.assessment.percent)%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(riskColor)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Scam risk")
            .accessibilityValue("\(engine.assessment.percent) percent, alert threshold \(thresholdPercent) percent")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(riskColor)
                        .frame(width: geo.size.width * clampedRisk)
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2)
                        .offset(x: min(max(geo.size.width * engine.threshold - 1, 0), max(geo.size.width - 2, 0)))
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)

            if engine.assessment.signals.isEmpty {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(engine.assessment.signals) { signal in
                            Text(signal.label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(riskColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(riskColor)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? Color.red : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text("LIVE TRANSCRIPT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if engine.lines.allSatisfy({ $0.text.isEmpty }) {
                Text(isActive ? "Listening…" : "Run the demo call, or listen live with a call on speaker.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(engine.lines) { line in
                    if !line.text.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.speaker.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .font(.body)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if isActive {
                Button(role: .destructive) {
                    engine.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    engine.runDemoCall()
                } label: {
                    Label("Run demo scam call", systemImage: "phone.arrow.down.left.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    engine.startListening()
                } label: {
                    Label("Listen live", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if engine.mode == .alerted || !engine.lines.isEmpty {
                    Button("Reset") {
                        engine.reset()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private var isActive: Bool {
        engine.mode == .demoCall || engine.mode == .listening
    }

    private var statusText: String {
        switch engine.mode {
        case .idle: return "Not listening"
        case .demoCall: return "Demo call in progress"
        case .listening: return "Listening for scam markers"
        case .alerted: return "Alert sent"
        }
    }

    private var riskColor: Color {
        let risk = engine.assessment.risk
        if risk >= engine.threshold { return .red }
        if risk >= 0.4 { return .orange }
        return .green
    }

    private var displayCaregiver: String {
        let name = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Maria" : name
    }

    /// Opens Messages with the alert filled in. The wearer still taps send:
    /// iOS doesn't let an app send a text silently, so automatic delivery needs a server.
    private func smsURL(for message: String) -> URL? {
        let number = caregiverPhone.filter { $0.isNumber || $0 == "+" }
        guard !number.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        guard let body = message.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "sms:\(number)?body=\(body)")
    }
}

struct SettingsView: View {
    @AppStorage("wearerName") private var wearerName = "Rosa"
    @AppStorage("caregiverName") private var caregiverName = "Maria"
    @AppStorage("caregiverPhone") private var caregiverPhone = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Wearing the band") {
                    TextField("Name", text: $wearerName)
                }
                Section("Caregiver") {
                    TextField("Name", text: $caregiverName)
                    TextField("Phone number", text: $caregiverPhone)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
