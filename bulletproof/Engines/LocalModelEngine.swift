import Foundation
import MLX
import MLXLMCommon

/// On-device inference against a downloaded Hugging Face snapshot via MLX.
/// Load-once residency and eviction live in LocalModelRuntime; this stays a
/// per-request value type like the other engines.
nonisolated struct LocalModelEngine: ProofreadingEngine {
    let modelDirectory: URL
    var runtime: ResidencyCache<ModelContainer> = LocalModelRuntime.shared
    var instructions = ProofreadPrompt.instructions

    func proofread(_ text: String) async throws -> String {
        // Checked before the model load - an oversized selection must not
        // cost a multi-gigabyte load it can never use.
        guard text.count <= Self.maxInputCharacters else {
            throw ProofreadingError.inputTooLong
        }
        let container: ModelContainer
        do {
            container = try await runtime.resource(for: modelDirectory)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProofreadingError.engineUnavailable(reason:
                "The local model couldn't be loaded. Re-download it in Settings > Models, or switch to Apple Intelligence.")
        }
        // Fresh KV cache per request: proofreading is stateless. No guided
        // generation on MLX - the instructions plus cleanResponse() are the
        // output-shaping mechanism. The system prompt is identical on every
        // call, so its KV cache is computed once and copied into each request
        // (prefill of ~460 prompt tokens dominated latency).
        let parameters = Self.parameters(for: text)
        let prefix = await PrefixCacheStore.shared.cache(for: instructions, container: container,
                                                         parameters: parameters)
        do {
            let response = try await Self.generate(prompt: ProofreadPrompt.userPrompt(for: text), text: text,
                                                   instructions: instructions, prefix: prefix,
                                                   container: container, parameters: parameters)
            await runtime.touch()
            let isDictation = instructions == ProofreadPrompt.dictationInstructions
            return ProofreadPrompt.cleanResponse(response, original: text,
                                                 keepsLowercase: !isDictation, sentenceCases: isDictation)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProofreadingError {
            throw error
        } catch {
            throw ProofreadingError.inferenceFailed(underlying: error)
        }
    }

    /// Generates token IDs and decodes them once at the end. ChatSession's
    /// streaming detokenizer diffs chunks by grapheme count, so a token that
    /// extends the previous character (a skin tone, a flag's second half, ZWJ,
    /// a variation selector, Thai or Devanagari vowel signs) was silently
    /// dropped: "👍🏽" came back "👍", "🇨🇦" as "🇨". Same prompt and tokens as
    /// ChatSession: [system, user], or [user] after the cached system prefix.
    static func generate(prompt: String, text: String, instructions: String, prefix: [KVCache]?,
                         container: ModelContainer, parameters: GenerateParameters) async throws -> String {
        try await container.perform(nonSendable: prefix) { context, prefix in
            var messages: [Chat.Message] = prefix == nil ? [.system(instructions)] : []
            messages.append(.user(prompt))
            let input = try await context.processor.prepare(input: UserInput(chat: messages))
            let cache = prefix ?? context.model.newCache(parameters: parameters)
            let promptTokens = (prefix?.first?.offset ?? 0) + input.text.tokens.size
            guard let maxTokens = tokenBudget(characterBudget: parameters.maxTokens ?? 0,
                                              inputTokens: context.tokenizer.encode(text: text).count,
                                              promptTokens: promptTokens) else {
                throw ProofreadingError.inputTooLong
            }
            var parameters = parameters
            parameters.maxTokens = maxTokens
            var tokens: [Int] = []
            for await generation in try generateTokens(input: input, cache: cache,
                                                       parameters: parameters, context: context) {
                if let token = generation.token { tokens.append(token) }
            }
            try Task.checkCancellation()
            return context.tokenizer.decode(tokenIds: tokens)
        }
    }

    /// The residency cache is single-flight, so this coalesces with the real
    /// request that follows it.
    func prewarm() async {
        _ = try? await runtime.resource(for: modelDirectory)
    }

    /// The generation budget in tokens, or nil when the text can't fit. The
    /// character estimate (3 chars per token) holds for English but not for
    /// Hindi, Tamil, Bengali or Burmese (1.3-3 tokens per character) or emoji
    /// runs (1.4), where it cut corrections short and pasted the truncated
    /// text. So the budget is never below the input's real token count x 2 +
    /// 128, and the whole exchange must fit the KV cache (no rotation).
    static func tokenBudget(characterBudget: Int, inputTokens: Int, promptTokens: Int) -> Int? {
        let needed = inputTokens * 2 + 128
        guard promptTokens + needed <= maxKVSize else { return nil }
        return min(max(characterBudget, needed), maxKVSize - promptTokens)
    }

    /// Corrections are roughly input-sized; 2x plus slack absorbs expansion
    /// without letting a runaway generation eat the 55s budget. ~3 chars per
    /// token is conservative for prose on these tokenizers.
    static func maxTokens(forInputLength characters: Int) -> Int {
        let estimatedInputTokens = max(16, characters / 3)
        return min(maxKVSize, estimatedInputTokens * 2 + 128)
    }

    /// The KV cache holds the whole exchange - instructions, wrapped input,
    /// and every generated token. Past this size the cache rotates and the
    /// model loses the start of the text it is rewriting.
    static let maxKVSize = 4096

    /// Largest input whose instructions + prompt + full generation budget
    /// still fit in the KV cache.
    static var maxInputCharacters: Int {
        ProofreadPrompt.maxInputCharacters(contextTokens: maxKVSize)
    }

    static func parameters(for text: String) -> GenerateParameters {
        var params = GenerateParameters(temperature: 0)
        params.maxTokens = maxTokens(forInputLength: text.count)
        params.maxKVSize = maxKVSize
        return params
    }
}


/// The system prompt's KV cache, built once per (model, instructions) and
/// handed out as copies. Only used when the chat template renders
/// [system, user] as exactly render([system]) + render([user]) in tokens -
/// otherwise callers fall back to a plain session.
actor PrefixCacheStore {
    static let shared = PrefixCacheStore()

    private final class Entry: @unchecked Sendable {
        let cache: [KVCache]
        init(_ cache: [KVCache]) { self.cache = cache }
    }

    private var entries: [String: Entry] = [:]
    private var containerID: ObjectIdentifier?

    func cache(for instructions: String, container: ModelContainer,
               parameters: GenerateParameters) async -> [KVCache]? {
        // A reloaded model invalidates every cached prefix.
        if containerID != ObjectIdentifier(container) {
            entries.removeAll()
            containerID = ObjectIdentifier(container)
        }
        if entries[instructions] == nil {
            guard let built = await Self.build(instructions: instructions, container: container,
                                               parameters: parameters) else { return nil }
            entries[instructions] = built
        }
        return entries[instructions].map { entry in entry.cache.map { $0.copy() } }
    }

    private static func build(instructions: String, container: ModelContainer,
                              parameters: GenerateParameters) async -> Entry? {
        await container.perform { context -> Entry? in
            let probe = ProofreadPrompt.userPrompt(for: "probe")
            let user: [[String: any Sendable]] = [["role": "user", "content": probe]]
            let system: [[String: any Sendable]] = [["role": "system", "content": instructions]]
            guard let full = try? context.tokenizer.applyChatTemplate(messages: system + user, tools: nil,
                                                                      additionalContext: nil),
                  let rest = try? context.tokenizer.applyChatTemplate(messages: user, tools: nil,
                                                                      additionalContext: nil),
                  full.count > rest.count, Array(full.suffix(rest.count)) == rest else { return nil }
            let prefix = Array(full.prefix(full.count - rest.count))
            let cache = context.model.newCache(parameters: parameters)
            _ = context.model(MLXArray(prefix).expandedDimensions(axis: 0), cache: cache)
            eval(cache.flatMap { $0.innerState() })
            return Entry(cache)
        }
    }
}
