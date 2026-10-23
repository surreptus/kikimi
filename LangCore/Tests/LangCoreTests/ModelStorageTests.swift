import XCTest
@testable import LangCore

/// Lets a test hold a download open until it decides to finish it.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

final class ModelStorageTests: XCTestCase {
    private func directory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mstore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// A model folder as WhisperKit lays it out; each required file is `bytes` long unless it is left out.
    @discardableResult
    private func writeModel(_ variant: String, in dir: URL, bytes: Int = 1_000, leaving out: Set<String> = []) throws -> URL {
        let folder = dir.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)")
        for file in ModelManager.requiredFiles where !out.contains(file) {
            let url = folder.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: url)
        }
        return folder
    }

    private func register(_ variant: String, in dir: URL, folder: URL) throws {
        let relative = String(folder.standardizedFileURL.path.dropFirst(dir.standardizedFileURL.path.count + 1))
        try JSONEncoder().encode([variant: relative]).write(to: dir.appending(path: "installed.json"))
    }

    func testListsEveryModelFolderWithItsSizeAndWhetherItIsComplete() async throws {
        let dir = directory()
        try writeModel("openai_whisper-medium", in: dir, bytes: 3_000)
        try writeModel("openai_whisper-tiny", in: dir, bytes: 500)
        try writeModel("openai_whisper-large-v3", in: dir, bytes: 1_000, leaving: ["AudioEncoder.mlmodelc/weights/weight.bin"])
        let manager = ModelManager(directory: dir)

        let models = await manager.installedModels()

        XCTAssertEqual(models.map(\.variant), ["openai_whisper-medium", "openai_whisper-large-v3", "openai_whisper-tiny"],
                       "largest first")
        XCTAssertEqual(models.map(\.bytes), [12_000, 3_000, 2_000], "four files of the given size each (three, for the incomplete one)")
        XCTAssertEqual(models.map(\.isComplete), [true, false, true], "the interrupted download is shown as incomplete")
    }

    func testNothingDownloadedListsNothing() async {
        let manager = ModelManager(directory: directory())
        let models = await manager.installedModels()
        XCTAssertTrue(models.isEmpty)
        let total = await manager.totalBytes()
        XCTAssertEqual(total, 0)
    }

    func testRemovingFreesTheSpaceAndForgetsTheModel() async throws {
        let dir = directory()
        let medium = try writeModel("openai_whisper-medium", in: dir, bytes: 2_000)
        try writeModel("openai_whisper-tiny", in: dir, bytes: 500)
        try register("openai_whisper-medium", in: dir, folder: medium)
        let manager = ModelManager(directory: dir)
        let installedBefore = await manager.isInstalled("openai_whisper-medium")
        XCTAssertTrue(installedBefore)

        let freed = try await manager.remove(variant: "openai_whisper-medium")

        XCTAssertEqual(freed, 8_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: medium.path))
        let installedAfter = await manager.isInstalled("openai_whisper-medium")
        XCTAssertFalse(installedAfter, "the index no longer points at it")
        let remaining = await manager.installedModels().map(\.variant)
        XCTAssertEqual(remaining, ["openai_whisper-tiny"], "other models are untouched")
    }

    func testAnIncompleteDownloadCanBeRemovedToo() async throws {
        let dir = directory()
        let partial = try writeModel("openai_whisper-medium", in: dir, leaving: ["TextDecoder.mlmodelc/weights/weight.bin"])
        let manager = ModelManager(directory: dir)
        let freed = try await manager.remove(variant: "openai_whisper-medium")
        XCTAssertGreaterThan(freed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testRemoveOnlyEverTouchesModelFolders() async throws {
        let dir = directory()
        try writeModel("openai_whisper-tiny", in: dir)
        let sentinel = dir.deletingLastPathComponent().appending(path: "precious-\(UUID().uuidString).txt")
        try Data("keep".utf8).write(to: sentinel)
        addTeardownBlock { try? FileManager.default.removeItem(at: sentinel) }
        let manager = ModelManager(directory: dir)

        for bad in ["", "..", "../\(sentinel.lastPathComponent)", "models", "nope", "openai_whisper-medium"] {
            do {
                try await manager.remove(variant: bad)
                XCTFail("expected notInstalled for '\(bad)'")
            } catch ModelError.notInstalled {}
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let remaining = await manager.installedModels().count
        XCTAssertEqual(remaining, 1, "nothing was removed")
    }

    func testCantRemoveAModelThatIsDownloadingRightNow() async throws {
        let dir = directory()
        let gate = Gate()
        let manager = ModelManager(directory: dir) { [self] variant, base, _ in
            await gate.wait()
            return try writeModel(variant, in: base)
        }
        let download = Task { try await manager.download(variant: "openai_whisper-medium") { _ in } }
        try await Task.sleep(for: .milliseconds(150))   // let it start and park at the gate

        do {
            try await manager.remove(variant: "openai_whisper-medium")
            XCTFail("expected busy")
        } catch ModelError.busy(let variant) {
            XCTAssertEqual(variant, "openai_whisper-medium")
            XCTAssertTrue(ModelError.busy(variant).errorDescription?.contains("downloading") ?? false)
        }

        await gate.open()
        _ = try await download.value
        let freed = try await manager.remove(variant: "openai_whisper-medium")
        XCTAssertGreaterThan(freed, 0, "once the download has finished it can be removed")
    }

    func testTotalCoversEverythingTheModelsFolderUses() async throws {
        let dir = directory()
        try writeModel("openai_whisper-tiny", in: dir, bytes: 1_000)
        try Data(repeating: 2, count: 700).write(to: dir.appending(path: "installed.json"))
        let manager = ModelManager(directory: dir)
        let total = await manager.totalBytes()
        XCTAssertEqual(total, 4_000 + 700)
    }
}

final class ModelCatalogTests: XCTestCase {
    func testEveryChoiceIsDescribedAndSizesGrowWithTheModel() {
        XCTAssertEqual(ModelPreferences.choices, ModelCatalog.all.map(\.variant))
        let sizes = ModelCatalog.all.map(\.downloadBytes)
        XCTAssertEqual(sizes, sizes.sorted(), "listed smallest to largest")
        XCTAssertTrue(ModelCatalog.all.allSatisfy { !$0.note.isEmpty && $0.downloadBytes > 0 })
    }

    func testEveryProfileDefaultIsInTheCatalogSoItAlwaysHasGuidance() {
        for profile in LanguageProfiles.all {
            XCTAssertNotNil(ModelCatalog.info(for: profile.defaultModel), profile.code)
        }
    }

    func testNamesAreReadableEvenForUnknownVariants() {
        XCTAssertEqual(ModelCatalog.name(for: "openai_whisper-medium"), "medium")
        XCTAssertEqual(ModelCatalog.name(for: "openai_whisper-large-v3-turbo"), "large-v3-turbo")
        XCTAssertEqual(ModelCatalog.name(for: "custom"), "custom")
    }

    func testNotesAdmitWhatWasNotMeasured() {
        let untested = ModelCatalog.all.filter { $0.name == "base" || $0.name == "small" }
        XCTAssertTrue(untested.allSatisfy { $0.note.contains("Not tested") }, "no invented claims about unmeasured models")
    }
}
