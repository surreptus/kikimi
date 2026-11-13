import LangCore
import SwiftUI

/// The raw text of a failure, folded away so the message stays plain. It can be selected and copied for a bug report.
struct ProblemDetails: View {
    let detail: String
    @State private var shown = false

    var body: some View {
        DisclosureGroup(isExpanded: $shown) {
            Text(detail)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Text("Show details").font(Theme.small)
        }
        .accessibilityHint("The technical text, for a bug report")
    }
}

/// A failure inline: what happened and what to do next, in red, with the details behind a disclosure.
struct ProblemView: View {
    let problem: Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problem.message).font(Theme.small).foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
            if !problem.detail.isEmpty { ProblemDetails(detail: problem.detail) }
        }
    }
}
