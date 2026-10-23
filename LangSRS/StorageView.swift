import LangCore
import SwiftUI

/// What the app keeps on this Mac that is large: downloaded speech models (removable here) and your videos
/// (removed from the Library).
struct StorageView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app
    @Environment(\.dismissModal) private var dismiss

    @State private var models: [InstalledModel] = []
    @State private var modelBytes: Int64 = 0
    @State private var videoCount = 0
    @State private var videoBytes: Int64 = 0
    @State private var removing: InstalledModel?
    @State private var error: String?

    private var importRunning: Bool { app.importQueue?.isBusy == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Storage").font(Theme.title(22))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
            }

            section("Speech models", bytes: modelBytes) {
                if models.isEmpty {
                    Text("No speech models are downloaded.").foregroundStyle(Theme.muted)
                }
                ForEach(models) { model in modelRow(model) }
                if importRunning {
                    Text("An import is running, so models can't be removed right now.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }

            section("Videos", bytes: videoBytes) {
                Text("\(videoCount) video\(videoCount == 1 ? "" : "s"). Delete them from the Library.")
                    .foregroundStyle(Theme.muted)
            }

            if let error { Text(error).font(.caption).foregroundStyle(Theme.red) }
        }
        .padding(24)
        .frame(width: 540)
        .background(Theme.page)
        .fontDesign(.rounded)
        .tint(Theme.accent)
        .task { await reload() }
        .confirmationDialog(
            "Remove the \(removing.map { ModelCatalog.name(for: $0.variant) } ?? "") model?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible, presenting: removing
        ) { model in
            Button("Remove and free \(format(model.bytes))", role: .destructive) { remove(model) }
        } message: { model in
            Text(removalMessage(for: model))
        }
    }

    private func section<Content: View>(_ title: String, bytes: Int64, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(Theme.title(16))
                Spacer()
                Text(format(bytes)).font(.system(.callout, design: .rounded, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            content()
        }
        .panel()
    }

    private func modelRow(_ model: InstalledModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelCatalog.name(for: model.variant)).font(.system(.headline, design: .rounded))
                Text(detail(for: model)).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(format(model.bytes)).foregroundStyle(Theme.muted)
            Button("Remove") { removing = model }
                .buttonStyle(.pill(.secondary, compact: true))
                .disabled(importRunning)
        }
    }

    private func detail(for model: InstalledModel) -> String {
        if !model.isComplete { return "Incomplete download. Downloading it again resumes where it stopped." }
        let users = languages(using: model).map(\.displayName)
        return users.isEmpty ? "Not in use" : "In use for \(users.joined(separator: " and "))"
    }

    private func languages(using model: InstalledModel) -> [any LanguageProfile] {
        LanguageProfiles.all.filter { env.preferences.model(for: $0) == model.variant }
    }

    private func removalMessage(for model: InstalledModel) -> String {
        let users = languages(using: model).map(\.displayName)
        let again = "You can download it again from Import."
        guard model.isComplete, !users.isEmpty else { return again }
        return "\(users.joined(separator: " and ")) imports use it, so you'll need to download a model before importing again. \(again)"
    }

    private func remove(_ model: InstalledModel) {
        Task {
            do {
                try await env.models.remove(variant: model.variant)
                error = nil
                await reload()
                app.dataChanged()   // so Import notices the model is gone
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func reload() async {
        models = await env.models.installedModels()
        modelBytes = await env.models.totalBytes()
        videoCount = (try? await env.database.libraryVideos().count) ?? 0
        videoBytes = env.libraryBytes()
    }

    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
