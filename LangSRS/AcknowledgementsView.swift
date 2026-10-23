import LangCore
import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.dismissModal) private var dismiss
    private let items = Acknowledgements.all()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Acknowledgements").font(Theme.title(22))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
            }
            .padding()
            List(items) { item in
                DisclosureGroup(item.title) {
                    Text(item.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 640, height: 520)
        .background(Theme.page)
        .fontDesign(.rounded)
        .tint(Theme.accent)
    }
}
