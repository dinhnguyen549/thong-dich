import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import os

/// Runs the translation model on the iPhone GPU with Apple MLX.
/// Models are loaded only from local folders; there is no download code path.
actor LLMTranslator {
    enum TranslatorError: LocalizedError {
        case notLoaded
        case notEnoughMemory(needGB: Double, freeGB: Double)

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "The translation model is not loaded."
            case .notEnoughMemory(let need, let free):
                return String(format: "Not enough free memory for this model (needs about %.1f GB, %.1f GB free). Close other apps or choose a smaller model in Settings.", need, free)
            }
        }
    }

    private var container: ModelContainer?
    private(set) var loadedModel: TranslatorModelID?

    var isLoaded: Bool { container != nil }

    // MARK: Loading

    func load(_ id: TranslatorModelID, from directory: URL) async throws {
        if loadedModel == id, container != nil { return }
        unload()

        // Make sure iOS will let us have the memory before trying (avoids being killed mid-load).
        let available = Int(os_proc_available_memory())
        let margin = 350 * 1_048_576
        if available > 0, available < id.estimatedMemoryBytes + margin {
            throw TranslatorError.notEnoughMemory(
                needGB: Double(id.estimatedMemoryBytes + margin) / 1_073_741_824,
                freeGB: Double(available) / 1_073_741_824)
        }

        // Keep MLX's reusable-buffer cache small so the speech engine and UI have room.
        Memory.cacheLimit = 192 * 1_048_576

        // TranslateGemma needs its special prompt format (language codes on every user turn).
        var generator: (any MLXLMCommon.MessageGenerator)? = nil
        if id.kind == .translationSpecialist { generator = TranslateGemma3MessageGenerator() }
        let configuration = ModelConfiguration(
            directory: directory,
            extraEOSTokens: [id.endOfTurnToken],
            messageGenerator: generator)

        container = try await LLMModelFactory.shared.loadContainer(
            from: OfflineOnlyDownloader(),
            using: LocalTokenizerLoader(),
            configuration: configuration)
        loadedModel = id

        // Warm-up: compiles the GPU kernels now, so the first real sentence is fast.
        let warm = TranslationRequest(
            text: "Good morning.", language: .english, mode: .everyday, pronouns: .automatic,
            dialect: .neutral, workField: .business, glossary: [], context: [], farField: false)
        _ = try? await translate(warm, onUpdate: { _ in })
    }

    func unload() {
        container = nil
        loadedModel = nil
        Memory.clearCache()
    }

    func trimCaches() {
        Memory.clearCache()
    }

    // MARK: Translation

    /// Translates one unit. `onUpdate` receives the growing Vietnamese text while it is generated.
    func translate(
        _ r: TranslationRequest,
        onUpdate: @Sendable (String) async -> Void
    ) async throws -> String {
        guard let container, let model = loadedModel else { throw TranslatorError.notLoaded }

        var messages: [Chat.Message] = []
        var additional: [String: any Sendable]? = nil
        switch model.kind {
        case .instruction:
            messages = [.system(PromptBuilder.systemPrompt(for: r)), .user(r.text)]
        case .translationSpecialist:
            // TranslateGemma takes no instructions; give it the last lines as earlier turns for context.
            for (source, vi) in r.context.suffix(2) {
                messages.append(.user(source))
                messages.append(.assistant(vi))
            }
            messages.append(.user(PromptBuilder.applyGlossaryToSource(r)))
            additional = ["source_lang_code": r.language.code, "target_lang_code": "vi"]
        }

        let input = UserInput(chat: messages, additionalContext: additional)
        let prepared = try await container.prepare(input: input)
        let words = TextTools.wordCount(r.text)
        let parameters = GenerateParameters(maxTokens: min(640, 48 + words * 5), temperature: 0)
        let stream = try await container.generate(input: prepared, parameters: parameters)

        var raw = ""
        var lastSent = ""
        var chunksSinceUpdate = 0
        for await event in stream {
            if Task.isCancelled { break }
            guard case .chunk(let piece) = event else { continue }
            raw += piece
            chunksSinceUpdate += 1
            if chunksSinceUpdate >= 3 {
                chunksSinceUpdate = 0
                let cleaned = PromptBuilder.clean(raw)
                if cleaned != lastSent {
                    lastSent = cleaned
                    await onUpdate(cleaned)
                }
            }
            if Self.isLooping(raw) { break }
        }
        return PromptBuilder.clean(raw)
    }

    /// Stops runaway repetition ("…và và và và…").
    private static func isLooping(_ text: String) -> Bool {
        guard text.count > 80 else { return false }
        let tail = String(text.suffix(24))
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: tail, range: searchRange) {
            count += 1
            if count >= 3 { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }
}

// MARK: - Adapters (local files only)

/// mlx-swift-lm asks for a downloader; this one refuses, guaranteeing no network access.
private struct OfflineOnlyDownloader: MLXLMCommon.Downloader {
    struct OfflineError: LocalizedError {
        var errorDescription: String? { "This app works offline only; model files must already be on the iPhone." }
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        throw OfflineError()
    }
}

/// Loads the tokenizer from the model folder with swift-transformers.
private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
