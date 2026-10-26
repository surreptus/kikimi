import LangCore
import SwiftUI

/// Corrects one transcript line. Saving also re-finds the words in it, so the word list matches what is said.
struct EditLineSheet: View {
    let line: Subtitle
    let profile: (any LanguageProfile)?
    let env: LangEnvironment
    let saved: (Subtitle) -> Void
    let cancel: () -> Void

    @State private var text: String
    @State private var failure: String?
    @State private var saving = false

    init(line: Subtitle, profile: (any LanguageProfile)?, env: LangEnvironment,
         saved: @escaping (Subtitle) -> Void, cancel: @escaping () -> Void) {
        self.line = line; self.profile = profile; self.env = env; self.saved = saved; self.cancel = cancel
        _text = State(initialValue: line.text)
    }

    private var changed: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines) != line.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit line").font(Theme.title(22))
            Text("Fix what the transcript got wrong. The timing stays the same, and the words in this line are found again.")
                .font(Theme.small).foregroundStyle(Theme.muted)
            TextEditor(text: $text)
                .font(.system(size: 17, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.soft))
                .accessibilityLabel("Line text")
            if let failure { Text(failure).font(Theme.small).foregroundStyle(Theme.red) }
            HStack {
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
            do { saved(try await env.database.editSubtitle(id: id, text: text, profile: profile)) }
            catch { failure = error.localizedDescription; saving = false }
        }
    }
}
