import Foundation

public enum AISetupTarget: CaseIterable {
    case chatGPT
    case claude
    case gemini

    public var title: String {
        switch self {
        case .chatGPT: return "ChatGPT / Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        }
    }
}

public enum AISetupGuide {
    public static let url = URL(string: "https://vela.basaapp.com/setup.md")!

    public static func prompt(helperPath: String, configurationDirectory: URL? = nil) -> String {
        let setupLocation = configurationDirectory?.path ?? "まだ作成されていません"
        return """
        Vela を初期設定したいです。次の導入手順を読んで、私の作業に合う設定を一緒に作ってください。

        \(url.absoluteString)

        今は Vela の設定フォルダは \(setupLocation) で、`vela.js`、`AGENT.md`、スキルファイルはまだありません。まず私に保存先を確認してください。指定がなければ `~/.config/vela` を使い、次のコマンドを実行して初期化してください。

        `\(helperPath) init --directory "<設定フォルダ>"`

        初期化により、設定フォルダに `vela.js`、`AGENT.md`、`.agent/skills/vela-configuration/` が作成されます。**初期化が終わるまで設定を提案・編集しないでください。**

        初期化後、このフォルダへアクセスできる場合は、設定を提案する前に AGENT.md、.agent/skills/vela-configuration/SKILL.md、その references/vela-js-api.md を読んでください。直接アクセスできない場合は、私に AGENT.md とスキルフォルダを会話へ添付するよう頼んでください。

        まず、私が頻繁に開くアプリ、使いたいショートカット、定型文、ウィンドウ操作について質問してください。設定を変更する前に、提案する内容とショートカットの衝突の可能性を説明し、私の確認を取ってください。設定後は `vela check` と `vela reload` の確認まで案内してください。
        """
    }

    public static func conversationURL(for target: AISetupTarget, helperPath: String, configurationDirectory: URL? = nil) -> URL? {
        let prompt = prompt(helperPath: helperPath, configurationDirectory: configurationDirectory)
        switch target {
        case .chatGPT:
            var components = URLComponents()
            components.scheme = "codex"
            components.host = "threads"
            components.path = "/new"
            components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]
            return components.url
        case .claude:
            var components = URLComponents()
            components.scheme = "claude"
            components.host = "claude.ai"
            components.path = "/new"
            components.queryItems = [URLQueryItem(name: "q", value: prompt)]
            return components.url
        case .gemini:
            return URL(string: "googlegemini://newchat")
        }
    }
}
