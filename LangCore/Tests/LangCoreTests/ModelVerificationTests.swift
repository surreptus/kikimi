import CryptoKit
import XCTest
@testable import LangCore

final class ModelManifestTests: XCTestCase {
    private static func isHex(_ text: String, length: Int) -> Bool {
        text.count == length && text.allSatisfy { "0123456789abcdef".contains($0) }
    }

    func testTheBundledManifestPinsAFullCommitOfTheRepositoryWhisperKitUses() {
        let manifest = ModelManifest.bundled
        XCTAssertEqual(manifest.repo, "argmaxinc/whisperkit-coreml")
        XCTAssertTrue(Self.isHex(manifest.commit, length: 40), "a commit, never a branch that moves")
    }

    func testEveryCatalogVariantIsInTheManifestAndNothingElse() {
        XCTAssertEqual(Set(ModelManifest.bundled.variants.keys), Set(ModelCatalog.all.map(\.variant)))
    }

    func testEveryWeightFileAModelNeedsIsListedWithASha256() {
        let weights = ModelManager.requiredFiles.filter { $0.hasSuffix("weight.bin") }
        for (variant, files) in ModelManifest.bundled.variants {
            let paths = Set(files.map(\.path))
            XCTAssertEqual(paths.count, files.count, "\(variant) lists a file twice")
            for weight in weights { XCTAssertTrue(paths.contains(weight), "\(variant) lacks \(weight)") }
            for file in files {
                XCTAssertTrue(Self.isHex(file.sha256, length: 64), "\(variant)/\(file.path)")
                XCTAssertGreaterThan(file.size, 0)
                XCTAssertFalse(file.path.hasPrefix("/") || file.path.contains(".."), "paths stay inside the model folder")
            }
        }
    }

    func testListedSizesAgreeWithTheDownloadSizeInTheCatalog() {
        for info in ModelCatalog.all {
            let listed = ModelManifest.bundled.files(for: info.variant)?.reduce(0) { $0 + $1.size } ?? 0
            // The catalog size also counts the few small files that are not listed, so the listed sum is a little smaller.
            XCTAssertLessThanOrEqual(listed, info.downloadBytes + info.downloadBytes / 100, info.variant)
            XCTAssertGreaterThan(listed, info.downloadBytes - info.downloadBytes / 20, info.variant)
        }
    }
}

final class ModelVerificationTests: XCTestCase {
    private func directory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mverify-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Writes `content` at `path` below `folder` and returns the manifest entry that describes it.
    @discardableResult
    private func put(_ content: Data, at path: String, in folder: URL) throws -> ModelManifest.File {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url)
        return ModelManifest.File(path: path, size: Int64(content.count), sha256: sha(content))
    }

    func testTheHashMatchesTheKnownValueForAFile() throws {
        let url = directory().appending(path: "abc.txt")
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(ModelVerifier.sha256(of: url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testAFileLargerThanOneReadBlockIsHashedWhole() throws {
        let folder = directory()
        let data = Data((0..<(9 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31) })   // 9 MB: three blocks
        let file = try put(data, at: "big.bin", in: folder)
        XCTAssertEqual(ModelVerifier.sha256(of: folder.appending(path: "big.bin")), file.sha256)
    }

    func testMatchingFilesPassAndStayInPlace() throws {
        let folder = directory()
        let files = [try put(Data(repeating: 7, count: 1_000), at: "a/weight.bin", in: folder),
                     try put(Data(repeating: 9, count: 20), at: "b.bin", in: folder)]
        XCTAssertEqual(ModelVerifier.deleteMismatches(of: files, in: folder), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "a/weight.bin").path))
    }

    func testOneFlippedByteFailsAndTheFileIsDeleted() throws {
        let folder = directory()
        let good = try put(Data(repeating: 7, count: 1_000), at: "good.bin", in: folder)
        let expected = try put(Data(repeating: 7, count: 1_000), at: "bad.bin", in: folder)
        var changed = Data(repeating: 7, count: 1_000)
        changed[500] ^= 1
        try changed.write(to: folder.appending(path: "bad.bin"))

        let bad = ModelVerifier.deleteMismatches(of: [good, expected], in: folder)

        XCTAssertEqual(bad, ["bad.bin"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "bad.bin").path), "never left to be used")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "good.bin").path), "other files are untouched")
    }

    func testAFileOfTheWrongSizeFailsAndIsDeleted() throws {
        let folder = directory()
        let expected = try put(Data(repeating: 7, count: 1_000), at: "short.bin", in: folder)
        try Data(repeating: 7, count: 999).write(to: folder.appending(path: "short.bin"))
        XCTAssertEqual(ModelVerifier.deleteMismatches(of: [expected], in: folder), ["short.bin"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "short.bin").path))
    }

    func testAMissingFileIsNotReportedHere() throws {
        let folder = directory()
        let file = ModelManifest.File(path: "gone.bin", size: 5, sha256: String(repeating: "0", count: 64))
        XCTAssertEqual(ModelVerifier.deleteMismatches(of: [file], in: folder), [], "the caller finds missing files")
    }
}

final class ModelDownloadVerificationTests: XCTestCase {
    private let variant = "openai_whisper-tiny"
    private let weight = "AudioEncoder.mlmodelc/weights/weight.bin"

    private func directory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "mdl-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// The content of each required file; the encoder weights are what a test corrupts.
    private func content(_ path: String) -> Data { Data(repeating: UInt8(path.utf8.count), count: 500 + path.utf8.count) }

    private func manifest(for variant: String) -> ModelManifest {
        let files = ModelManager.requiredFiles.filter { $0.hasSuffix("weight.bin") }
            .map { ModelManifest.File(path: $0, size: Int64(content($0).count), sha256: sha(content($0))) }
        return ModelManifest(repo: "test/repo", commit: String(repeating: "1", count: 40), variants: [variant: files])
    }

    private func folder(of variant: String, in base: URL) -> URL { base.appending(path: "models/test/repo/\(variant)") }

    /// Lays out a model folder; `corrupt` files get one flipped byte.
    private func writeModel(_ variant: String, in base: URL, corrupt: Set<String> = []) throws -> URL {
        let root = folder(of: variant, in: base)
        for path in ModelManager.requiredFiles {
            var data = content(path)
            if corrupt.contains(path) { data[0] ^= 1 }
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return root
    }

    private func index(_ dir: URL) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: dir.appending(path: "installed.json")))
    }

    func testACorruptDownloadIsRejectedDeletedAndNeverRecorded() async throws {
        let dir = directory()
        // Another model is already installed. Its entry must survive.
        let other = try writeModel("openai_whisper-base", in: dir)
        try JSONEncoder().encode(["openai_whisper-base": "models/test/repo/openai_whisper-base"]).write(to: dir.appending(path: "installed.json"))
        let calls = LockedBox(0)
        let manager = ModelManager(directory: dir, manifest: manifest(for: variant)) { [self] variant, base, _ in
            calls.mutate { $0 += 1 }
            return try writeModel(variant, in: base, corrupt: [weight])
        }

        do {
            try await manager.download(variant: variant, attempts: 2) { _ in }
            XCTFail("expected verificationFailed")
        } catch let ModelError.verificationFailed(model, files) {
            XCTAssertEqual(model, variant)
            XCTAssertEqual(files, [weight])
        }

        XCTAssertEqual(calls.value, 2, "the bad file is deleted and the download is tried again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder(of: variant, in: dir).appending(path: weight).path))
        let installed = await manager.isInstalled(variant)
        XCTAssertFalse(installed)
        XCTAssertEqual(try index(dir), ["openai_whisper-base": "models/test/repo/openai_whisper-base"], "the old index is kept as it was")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.appending(path: weight).path))
    }

    func testABadFileIsFetchedAgainOnTheNextAttempt() async throws {
        let dir = directory()
        let calls = LockedBox(0)
        let manager = ModelManager(directory: dir, manifest: manifest(for: variant)) { [self] variant, base, _ in
            let attempt = calls.mutateReturning { $0 += 1; return $0 }
            return try writeModel(variant, in: base, corrupt: attempt == 1 ? [weight] : [])
        }
        let result = try await manager.download(variant: variant) { _ in }
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(try index(dir)[variant], "models/test/repo/\(variant)")
        XCTAssertEqual(result.lastPathComponent, variant)
    }

    func testAGoodDownloadIsRecordedOnlyAfterTheCheck() async throws {
        let dir = directory()
        let manager = ModelManager(directory: dir, manifest: manifest(for: variant)) { [self] variant, base, _ in
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "installed.json").path), "nothing recorded yet")
            return try writeModel(variant, in: base)
        }
        try await manager.download(variant: variant) { _ in }
        let installed = await manager.isInstalled(variant)
        XCTAssertTrue(installed)
    }

    func testAVariantWithoutCheckedValuesIsNotDownloaded() async throws {
        let calls = LockedBox(0)
        let manager = ModelManager(directory: directory(), manifest: manifest(for: variant)) { variant, base, _ in
            calls.mutate { $0 += 1 }
            return base
        }
        do {
            try await manager.download(variant: "openai_whisper-unknown") { _ in }
            XCTFail("expected notAvailable")
        } catch ModelError.notAvailable(let model) {
            XCTAssertEqual(model, "openai_whisper-unknown")
        }
        XCTAssertEqual(calls.value, 0, "nothing is fetched that cannot be checked")
    }

    func testAnEarlierInstallIsNotCheckedAgain() async throws {
        // Models installed before the check existed stay usable. Their files do not match the fake manifest, and nothing complains.
        let dir = directory()
        let root = try writeModel(variant, in: dir, corrupt: [weight])
        try JSONEncoder().encode([variant: "models/test/repo/\(variant)"]).write(to: dir.appending(path: "installed.json"))
        let manager = ModelManager(directory: dir, manifest: manifest(for: variant))
        let found = await manager.installedFolder(for: variant)
        XCTAssertEqual(found?.standardizedFileURL, root.standardizedFileURL)
    }

    func testTheMessageSaysWhatHappenedAndWhatToDo() {
        let message = ModelError.verificationFailed(variant, files: [weight]).errorDescription ?? ""
        XCTAssertTrue(message.contains("damaged"))
        XCTAssertTrue(message.contains("deleted"))
        XCTAssertTrue(message.contains("download again"))
        XCTAssertTrue(message.contains("tiny"), "it names the model by its short name")
    }
}
