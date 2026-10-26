import LangCore
import SwiftUI

/// Corrects one transcript line. Saving also re-finds the words in it, so the word list matches what is said.
struct EditLineSheet: View {
    let line: Subtitle
    let duration: Double
    let profile: (any LanguageProfile)?
    let env: LangEnvironment
    let preview: (Double, Double) -> Void
    let saved: (Subtitle) -> Void
    let cancel: () -> Void

    @State private var text: String
    @State private var start: Double
    @State private var end: Double
    @State private var failure: String?
    @State private var saving = false

    init(line: Subtitle, duration: Double, profile: (any LanguageProfile)?, env: LangEnvironment,
         preview: @escaping (Double, Double) -> Void, saved: @escaping (Subtitle) -> Void, cancel: @escaping () -> Void) {
        self.line = line; self.duration = duration; self.profile = profile; self.env = env
        self.preview = preview; self.saved = saved; self.cancel = cancel
        _text = State(initialValue: line.text)
        _start = State(initialValue: line.startTime)
        _end = State(initialValue: line.endTime)
    }

    private var textChanged: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines) != line.text }
    private var timingChanged: Bool { abs(start - line.startTime) > 0.001 || abs(end - line.endTime) > 0.001 }
    private var changed: Bool { textChanged || timingChanged }

    private func clock(_ seconds: Double) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit line").font(Theme.title(22))
            Text("Fix what the transcript got wrong. The words in this line are found again.")
                .font(Theme.small).foregroundStyle(Theme.muted)
            TextEditor(text: $text)
                .font(.system(size: 17, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.soft))
                .accessibilityLabel("Line text")
            HStack(spacing: 18) {
                Stepper(value: $start, in: 0...max(0, end - 0.2), step: 0.1) { Text("Starts \(clock(start))").monospacedDigit() }
                Stepper(value: $end, in: (start + 0.2)...max(start + 0.2, duration), step: 0.1) { Text("Ends \(clock(end))").monospacedDigit() }
            }
            .font(Theme.small)
            if let failure { Text(failure).font(Theme.small).foregroundStyle(Theme.red) }
            HStack {
                Button("Play this part", systemImage: "play.fill") { preview(start, end) }
                    .buttonStyle(.pill(.secondary, compact: true))
                    .help("Plays from the start to the end you've set, so you can check it")
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.pill(.secondary, compact: true)).keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.pill(compact: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!changed || saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.card)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .fontDesign(.rounded)
    }

    private func save() {
        guard let profile, let id = line.id else { return }
        saving = true
        Task {
            do {
                saved(try await env.database.editSubtitle(
                    id: id, text: text, start: timingChanged ? start : nil, end: timingChanged ? end : nil, profile: profile))
            }
            catch { failure = error.localizedDescription; saving = false }
        }
    }
}
