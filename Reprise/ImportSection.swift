import LangCore
import SwiftUI
import UniformTypeIdentifiers

/// Adding videos: the speech model, the drop area and the progress of each import. It sits at the top of the Videos page.
struct ImportSection: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var model = ""
    @State private var modelInstalled: Bool?
    @State private var downloadProgress: Double?
    @State private var downloadError: String?
    @State private var isTargeted = false
    @State private var showImporter = false
    /// The model choice is set once and then stays out of the way; this opens it again.
    @State private var changingModel = false

    private var queue: ImportQueue { app.importQueue! }
    private var canImport: Bool { modelInstalled == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            modelSection
            dropZone
            if !queue.jobs.isEmpty { jobList }
        }
        .task(id: app.languageCode) { await loadModel() }
        .onChange(of: app.dataVersion) { Task { await refreshInstalled() } }   // e.g. a model removed in Storage
        .onChange(of: app.addVideosPending) { _, pending in if pending { openChooserIfReady() } }
        .task { if app.addVideosPending { openChooserIfReady() } }
        .onChange(of: queue.jobs.map(\.status)) { _, statuses in
            if statuses.contains(.imported) { app.dataChanged() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .audiovisualContent],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { start(urls) }
        }
    }

    // MARK: Model

    /// Quiet once it's ready: a single line, with the choice one click away. The full card appears only when a
    /// model has to be downloaded or you ask to change it.
    @ViewBuilder
    private var modelSection: some View {
        if modelInstalled == true, downloadProgress == nil, !changingModel {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text("Speech model ready: \(modelShortName)").font(.callout).foregroundStyle(Theme.muted)
                Button("Change") { changingModel = true }
                    .buttonStyle(.plain)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
        } else {
            modelCard
        }
    }

    private var modelShortName: String {
        ModelCatalog.name(for: env.preferences.model(for: app.profile))
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.and.mic").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                Text("Speech model").font(.system(.headline, design: .rounded))
                if model.isEmpty {
                    ProgressView().controlSize(.small)   // selection not loaded yet; a Picker would warn about ""
                } else {
                    Picker("Speech model", selection: $model) {
                        ForEach(modelChoices, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: model) { _, new in
                        env.preferences.setModel(new == app.profile.defaultModel ? nil : new, for: app.profile)
                        Task { await refreshInstalled() }
                    }
                }
                Spacer()
                if let progress = downloadProgress {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: progress).progressViewStyle(.thin).frame(width: 160)
                        Text("\(Int(progress * 100))%").font(Theme.small.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                } else if modelInstalled == false {
                    Button("Download model") { Task { await download() } }.buttonStyle(.pill(compact: true))
                } else if modelInstalled == true {
                    Button("Done") { changingModel = false }.buttonStyle(.pill(.secondary, compact: true))
                }
            }
            if let note = ModelCatalog.info(for: model)?.note {
                Text(note).font(Theme.small).foregroundStyle(Theme.muted)
            }
            if let downloadError {
                Text(downloadError).font(Theme.small).foregroundStyle(Theme.red)
            }
        }
        .panel()
    }

    private var modelChoices: [String] {
        let all = ModelPreferences.choices
        return all.contains(app.profile.defaultModel) ? all : [app.profile.defaultModel] + all
    }

    /// "medium · 1.5 GB (recommended)": the size, and a flag on the model suggested for this language.
    private func label(for variant: String) -> String {
        let size = ModelCatalog.info(for: variant)
            .map { " · " + ByteCountFormatter.string(fromByteCount: $0.downloadBytes, countStyle: .file) } ?? ""
        return ModelCatalog.name(for: variant) + size + (variant == app.profile.defaultModel ? " (recommended)" : "")
    }

    private func loadModel() async {
        changingModel = false
        model = env.preferences.model(for: app.profile)
        await refreshInstalled()
    }

    /// File > Add Videos…. Without a speech model there is nothing to import into, so the page just shows the model card.
    private func openChooserIfReady() {
        app.addVideosPending = false
        if canImport { showImporter = true }
    }

    private func refreshInstalled() async {
        model = env.preferences.model(for: app.profile)   // it may have been changed in Settings
        modelInstalled = nil
        let variant = env.preferences.model(for: app.profile)
        modelInstalled = await env.models.isInstalled(variant)
    }

    private func download() async {
        let variant = env.preferences.model(for: app.profile)
        downloadError = nil
        downloadProgress = 0
        do {
            try await env.models.download(variant: variant) { p in Task { @MainActor in downloadProgress = p } }
        } catch {
            downloadError = error.localizedDescription
        }
        downloadProgress = nil
        await refreshInstalled()
        if modelInstalled == true { changingModel = false }   // done: fold the card away again
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Text(canImport ? "Drop \(app.profile.displayName) videos here" : "Download the speech model to start importing")
                .font(Theme.title(20))
            Text("Importing as \(app.profile.displayName). Change the language in the sidebar.")
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Your original files are never changed or deleted.")
                .font(.callout).foregroundStyle(Theme.muted)
            Button("Choose files") { showImporter = true }
                .buttonStyle(.pill)
                .disabled(!canImport)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(RoundedRectangle(cornerRadius: 26).fill(isTargeted ? Theme.soft : Theme.soft.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 26)
            .strokeBorder(Theme.ink.opacity(isTargeted ? 0.7 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7])))
        .scaleEffect(isTargeted ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard canImport else { return false }
            start(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func start(_ urls: [URL]) {
        let media = urls.filter {
            UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audiovisualContent) ?? false
        }
        queue.enqueue(media, profile: app.profile, model: env.preferences.model(for: app.profile))
    }

    // MARK: Jobs

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(queue.jobs) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(job.fileName).font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        StatusPill(text: statusText(job), color: statusColor(job.status))
                        if canCancel(job.status) {
                            Button("Cancel") { queue.cancel(job.id) }.buttonStyle(.pill(.secondary, compact: true))
                                .help("Stop this import. Your original file is untouched.")
                        }
                    }
                    if case .running(_, let fraction) = job.status {
                        ProgressView(value: fraction).progressViewStyle(.thin)
                    }
                    if case .failed(let message) = job.status {
                        Text(message).font(Theme.small).foregroundStyle(Theme.red)
                    }
                    if case .languageMismatch(let detected) = job.status, let other = LanguageProfiles.profile(for: detected) {
                        languagePrompt(job: job, detected: other)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Clear finished") { queue.clearFinished() }
                    .buttonStyle(.pill(.secondary, compact: true))
                    .disabled(queue.isBusy && queue.jobs.count == 1)
            }
        }
        .panel()
    }

    /// Asked when the audio sounds like a different supported language than the one selected.
    private func languagePrompt(job: ImportQueue.Job, detected other: any LanguageProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This sounds like \(other.displayName), but you're importing as \(job.profile.displayName). Nothing has been imported yet.")
                .font(.callout)
            HStack(spacing: 10) {
                Button("Import as \(other.displayName)") {
                    queue.retry(job.id, as: other, model: env.preferences.model(for: other))
                }
                .buttonStyle(.pill(compact: true))
                Button("Import as \(job.profile.displayName) anyway") { queue.importAnyway(job.id) }
                    .buttonStyle(.pill(.secondary, compact: true))
                Button("Cancel") { queue.cancel(job.id) }.buttonStyle(.pill(.secondary, compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.soft))
    }

    private func statusText(_ job: ImportQueue.Job) -> String {
        switch job.status {
        case .queued: "Waiting"
        case .running(let stage, _): runningText(stage, job)
        case .imported: "Imported · \(job.profile.displayName)"
        case .duplicate: "Already in library"
        case .languageMismatch: "Check language"
        case .cancelling: "Cancelling…"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }

    /// Waiting or running jobs can be cancelled; one already cancelling can't be asked twice.
    private func canCancel(_ status: ImportQueue.Status) -> Bool {
        switch status {
        case .queued, .running: true
        default: false
        }
    }

    private func statusColor(_ status: ImportQueue.Status) -> Color {
        switch status {
        case .imported: Theme.green
        case .failed: Theme.red
        case .languageMismatch, .cancelling: Theme.orange
        case .running: Theme.ink
        default: .secondary
        }
    }

    /// "3 of 8 · Transcribing": the step's place in the import (out of 7 if the language check was skipped).
    private func runningText(_ stage: ImportStage, _ job: ImportQueue.Job) -> String {
        let place = stage.position(checkingLanguage: job.checksLanguage)
        return "\(place.number) of \(place.of) · \(stageName(stage))"
    }

    private func stageName(_ stage: ImportStage) -> String {
        switch stage {
        case .hashing: "Reading file"
        case .staging: "Copying"
        case .detectingLanguage: "Checking language"
        case .transcribing: "Transcribing"
        case .transcoding: "Compressing video"
        case .verifying: "Verifying"
        case .extractingAudio: "Extracting audio"
        case .saving: "Saving"
        }
    }
}
