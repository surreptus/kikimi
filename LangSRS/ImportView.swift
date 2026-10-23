import LangCore
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    let env: LangEnvironment
    @Environment(AppState.self) private var app

    @State private var model = ""
    @State private var modelInstalled: Bool?
    @State private var downloadProgress: Double?
    @State private var downloadError: String?
    @State private var isTargeted = false
    @State private var showImporter = false

    private var queue: ImportQueue { app.importQueue! }
    private var canImport: Bool { modelInstalled == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(text: "Import", subtitle: "Drop videos you own. Everything stays on this Mac.")
                modelSection
                dropZone
                if !queue.jobs.isEmpty { jobList }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle("Import")
        .task(id: app.languageCode) { await loadModel() }
        .onChange(of: queue.jobs.map(\.status)) { _, statuses in
            if statuses.contains(.imported) { app.dataChanged() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .audiovisualContent],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { start(urls) }
        }
    }

    // MARK: Model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.and.mic").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.pink)
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
                        ProgressView(value: progress).progressViewStyle(.duo).frame(width: 160)
                        Text("\(Int(progress * 100))%").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                } else if modelInstalled == false {
                    Button("Download model") { Task { await download() } }.buttonStyle(.chunky(compact: true))
                } else if modelInstalled == true {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.green)
                }
            }
            if let downloadError {
                Text(downloadError).font(.caption).foregroundStyle(Theme.red)
            }
        }
        .duoCard()
    }

    private var modelChoices: [String] {
        let all = ModelPreferences.choices
        return all.contains(app.profile.defaultModel) ? all : [app.profile.defaultModel] + all
    }

    private func label(for variant: String) -> String {
        let name = variant.replacingOccurrences(of: "openai_whisper-", with: "")
        return variant == app.profile.defaultModel ? "\(name) (default)" : name
    }

    private func loadModel() async {
        model = env.preferences.model(for: app.profile)
        await refreshInstalled()
    }

    private func refreshInstalled() async {
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
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.fill").font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.pink)
            Text(canImport ? "Drop \(app.profile.displayName) videos here" : "Download the speech model to start importing")
                .font(Theme.title(20))
            Text("Importing as \(app.profile.displayName). Change the language in the sidebar.")
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.pinkText)
            Text("Your original files are never changed or deleted.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Choose files") { showImporter = true }
                .buttonStyle(.chunky)
                .disabled(!canImport)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(RoundedRectangle(cornerRadius: 26).fill(isTargeted ? Theme.pinkSoft : Theme.pinkSoft.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 26)
            .strokeBorder(Theme.pink.opacity(isTargeted ? 1 : 0.7), style: StrokeStyle(lineWidth: 3, dash: [11, 9])))
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
                    }
                    if case .running(_, let fraction) = job.status {
                        ProgressView(value: fraction).progressViewStyle(.duo)
                    }
                    if case .failed(let message) = job.status {
                        Text(message).font(.caption).foregroundStyle(Theme.red)
                    }
                    if case .languageMismatch(let detected) = job.status, let other = LanguageProfiles.profile(for: detected) {
                        languagePrompt(job: job, detected: other)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Clear finished") { queue.clearFinished() }
                    .buttonStyle(.chunky(.secondary, compact: true))
                    .disabled(queue.isBusy && queue.jobs.count == 1)
            }
        }
        .duoCard()
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
                .buttonStyle(.chunky(compact: true))
                Button("Import as \(job.profile.displayName) anyway") { queue.importAnyway(job.id) }
                    .buttonStyle(.chunky(.secondary, compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.pinkSoft))
    }

    private func statusText(_ job: ImportQueue.Job) -> String {
        switch job.status {
        case .queued: "Waiting"
        case .running(let stage, _): stageName(stage)
        case .imported: "Imported · \(job.profile.displayName)"
        case .duplicate: "Already in library"
        case .languageMismatch: "Check language"
        case .failed: "Failed"
        }
    }

    private func statusColor(_ status: ImportQueue.Status) -> Color {
        switch status {
        case .imported: Theme.green
        case .failed: Theme.red
        case .languageMismatch: Theme.orange
        case .running: Theme.pinkText
        default: .secondary
        }
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
