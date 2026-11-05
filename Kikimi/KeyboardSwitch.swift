import AppKit

/// Switches the text field being typed in to a keyboard that suits the language, and puts the Mac's own keyboard back
/// afterwards. Only keyboards the learner has already added in System Settings can be chosen; if there is none, nothing
/// changes. Nothing is read beyond the names of the installed keyboards, and nothing is stored or sent.
@MainActor
enum KeyboardSwitch {
    private static var before: (context: NSTextInputContext, source: String)?

    /// Call once the text field has focus. A Japanese keyboard in romaji form is preferred, since that is typed with
    /// the same keys as the other languages.
    static func use(keywords: [String]) {
        guard !keywords.isEmpty, let context = (NSApp.keyWindow?.firstResponder as? NSTextView)?.inputContext,
              let sources = context.keyboardInputSources, let current = context.selectedKeyboardInputSource else { return }
        let wanted = keywords.map { $0.lowercased() }
        func fits(_ source: String) -> Bool { wanted.contains { source.lowercased().contains($0) } }
        guard !fits(current) else { return }
        let options = sources.filter(fits)
        guard let choice = options.first(where: { $0.lowercased().contains("romaji") }) ?? options.first else { return }
        before = (context, current)
        context.selectedKeyboardInputSource = choice
    }

    static func restore() {
        guard let before else { return }
        before.context.selectedKeyboardInputSource = before.source
        self.before = nil
    }
}
