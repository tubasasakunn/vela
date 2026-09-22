import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Chooses a configured candidate using Apple Private Cloud Compute (PCC) when
/// it is available. A deterministic order remains available everywhere.
public enum ContextSnippetRanker {
    public static func rank(
        _ snippets: [ContextSnippetConfiguration],
        for context: FocusedInputContext
    ) async -> [ContextSnippetConfiguration] {
        guard !snippets.isEmpty else { return [] }
        let fallback = rankedByText(snippets, context: context)
        #if canImport(FoundationModels)
        guard #available(macOS 27.0, *) else { return fallback }
        do {
            let selection = try await select(snippets, context: context)
            guard let selected = snippets.first(where: { $0.name == selection.name }) else { return fallback }
            return [selected] + fallback.filter { $0.name != selected.name }
        } catch {
            return fallback
        }
        #else
        return fallback
        #endif
    }

    private static func rankedByText(_ snippets: [ContextSnippetConfiguration], context: FocusedInputContext) -> [ContextSnippetConfiguration] {
        let terms = Set((context.label + " " + context.applicationName)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .filter { $0.count > 1 }
            .map(String.init))
        return snippets.enumerated().sorted { lhs, rhs in
            let left = score(lhs.element, terms: terms)
            let right = score(rhs.element, terms: terms)
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    private static func score(_ snippet: ContextSnippetConfiguration, terms: Set<String>) -> Int {
        let candidateTerms = Set((snippet.name + " " + snippet.description)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init))
        return terms.intersection(candidateTerms).count
    }
}

#if canImport(FoundationModels)
@available(macOS 27.0, *)
private extension ContextSnippetRanker {
    @Generable(description: "The name of exactly one supplied context snippet.")
    struct Selection {
        @Guide(description: "Copy one candidate name exactly. Do not invent a name.")
        var name: String
    }

    static func select(_ snippets: [ContextSnippetConfiguration], context: FocusedInputContext) async throws -> Selection {
        let choices = snippets.map { "- name: \($0.name)\n  description: \($0.description)" }.joined(separator: "\n")
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else { throw PCCUnavailableError() }
        let session = LanguageModelSession(
            model: model,
            instructions: "Choose the one configured paste candidate that best matches a focused input field. Use only its label and the candidate descriptions. Never infer or request private text. Return exactly one supplied name."
        )
        let response = try await session.respond(
            to: "Application: \(context.applicationName)\nInput role: \(context.role)\nAccessible field label: \(context.label)\n\nCandidates:\n\(choices)",
            generating: Selection.self
        )
        return response.content
    }

    private struct PCCUnavailableError: Error {}
}
#endif
