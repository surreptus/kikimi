import CMeCab
import Foundation

public enum MeCabError: Error {
    case modelFailed(String)
}

/// MeCab morphological analyser. Knows nothing about any dictionary's tag set: the profile that supplies
/// the dictionary also supplies `interpret`, which maps a node's surface and feature fields to a `Token`.
public final class MeCabTokenizer: WordTokenizer, @unchecked Sendable {
    public typealias Interpreter = @Sendable (_ surface: String, _ features: [String]) -> Token?

    // The model is immutable and thread-safe; a tagger (not thread-safe) is created per call.
    private let model: OpaquePointer
    private let interpret: Interpreter

    public init(dictionaryDirectory: URL, interpret: @escaping Interpreter) throws {
        let args = ["mecab", "-r", "/dev/null", "-d", dictionaryDirectory.path]
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }
        guard let model = mecab_model_new(Int32(cArgs.count), &cArgs) else {
            throw MeCabError.modelFailed(String(cString: mecab_strerror(nil)))
        }
        self.model = model
        self.interpret = interpret
    }

    deinit { mecab_model_destroy(model) }

    public func tokens(in text: String) -> [Token] {
        guard let tagger = mecab_model_new_tagger(model) else { return [] }
        defer { mecab_destroy(tagger) }

        var result: [Token] = []
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            let base = UnsafeRawPointer(buffer.baseAddress).map { $0.assumingMemoryBound(to: CChar.self) }
            var node = mecab_sparse_tonode2(tagger, base, buffer.count)
            while let current = node?.pointee {
                defer { node = current.next.map { UnsafePointer($0) } }
                guard current.stat == UInt8(MECAB_NOR_NODE) || current.stat == UInt8(MECAB_UNK_NODE) else { continue }
                let surface = String(
                    decoding: UnsafeRawBufferPointer(start: current.surface, count: Int(current.length)),
                    as: UTF8.self)
                let features = String(cString: current.feature).split(separator: ",", omittingEmptySubsequences: false)
                    .map(String.init)
                if let token = interpret(surface, features) { result.append(token) }
            }
        }
        return result
    }
}
