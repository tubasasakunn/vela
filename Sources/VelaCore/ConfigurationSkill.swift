import Foundation

/// Writes the AI-facing documentation that accompanies a Vela configuration.
/// User-edited skill files are preserved on subsequent `vela init` runs.
public enum ConfigurationSkill {
    public static func write(to configurationDirectory: URL) throws {
        let skillDirectory = configurationDirectory
            .appending(path: ".agent/skills/vela-configuration", directoryHint: .isDirectory)
        try write(agentInstructions, to: configurationDirectory.appending(path: "AGENT.md"))
        try write(source, to: skillDirectory.appending(path: "SKILL.md"))
        try write(apiReference, to: skillDirectory.appending(path: "references/vela-js-api.md"))
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let agentInstructions = """
    # Vela configuration workspace

    This directory contains the active Vela configuration (`vela.js`). Use the
    `vela-configuration` skill at `.agent/skills/vela-configuration/SKILL.md`
    before creating, explaining, or editing that file. Its API reference is at
    `.agent/skills/vela-configuration/references/vela-js-api.md`.

    Vela can provide a launcher, clipboard history, global hotkeys, window
    positioning and switching, text capture from a screen area, keyword searches,
    searchable commands, fixed-text snippets, and context-aware paste candidates. Ask the
    user what workflow they want and confirm the proposed hotkeys, commands,
    snippets, and any shell action before writing or changing `vela.js`. Preserve
    unrelated settings. After an approved edit, run `vela check`, then `vela
    reload` when Vela is running, and ask the user to test newly assigned
    shortcuts.
    """

    private static let source = """
    ---
    name: vela-configuration
    description: Create, explain, or safely edit Vela's JavaScript configuration (`vela.js`), including hotkeys, commands, keyword searches, snippets, window actions, and focused-field snippets. Use for Vela user configuration, not Vela application-source changes.
    ---

    # Vela Configuration

    Vela is configured through one ordinary JavaScript file named `vela.js`. Produce a small, usable configuration that reflects the user's stated workflow; do not add commands, hotkeys, personal data, or shell actions merely to demonstrate an API.

    ## Locate and preserve the configuration

    Before changing a real configuration, inspect the active path with `vela doctor` and read the existing file. Its default location is `~/.config/vela/vela.js`. `VELA_CONFIG_HOME` overrides the active directory, and an installation can also persist a chosen directory. Do not assume the default path is active.

    Make the smallest edit that satisfies the request. Preserve unrelated declarations, comments, and ordering. If a requested hotkey is already present, ask whether it should replace the existing action rather than silently creating a collision. Never overwrite an existing configuration with `vela init`.

    ## Choose the right mechanism

    - Use `Vela.configure` for launcher, clipboard, switcher, and contextual-snippet behavior.
    - Use `Vela.hotkey` for one fixed action bound to a global shortcut.
    - Use `Vela.command` for a searchable palette item that launches a shell command, URL, or installed application.
    - Use `Vela.search` for a URL search activated by a short keyword followed by a query, such as `g Swift URL`.
    - Use `Vela.snippet` for fixed text selected by the user.
    - Use `contextSnippets` only for a small set of paste candidates whose use can be inferred from a focused field's accessible label or description. Keep them concrete, accurate, and free of secrets.

    Read [the API reference](references/vela-js-api.md) before writing or modifying JavaScript. It lists every supported API and its validation constraints.

    ## Configuration boundaries

    While Vela loads `vela.js`, its JavaScript environment exposes only `Vela`; it cannot read files, access the network, or inspect environment variables. Callback bodies are evaluated to describe an action, so they must return one of Vela's supported action constructors—not arbitrary JavaScript work.

    `Vela.shell` runs its string later as `/bin/zsh -lc`. Treat it as executable user configuration: quote paths correctly, avoid destructive commands unless explicitly requested, and do not interpolate untrusted input. Prefer `Vela.openURL`, `Vela.search`, or `Vela.application` when they express the desired action directly.

    ## Validate and activate

    After editing, run `vela check`. It detects JavaScript/API failures, unknown or mistyped properties, malformed and duplicate hotkeys (including modifier aliases), unusable command actions, duplicate IDs/names, blank required fields, and clipboard limits outside 1...10,000. Then use `vela reload` when the Vela app is running; it waits for the app to accept or reject the new configuration.

    For changes that assign a shortcut, tell the user to test it. `vela reload` reports registration conflicts that macOS exposes, but another app can still consume the same keystroke without declaring a global registration.
    """

    private static let apiReference = """
    # Vela JavaScript configuration API

    All declarations are evaluated as `vela.js` loads. Use one or more `Vela.configure(...)` calls; a later call replaces only the sections it supplies. Every `Vela.hotkey`, `Vela.command`, `Vela.search`, and `Vela.snippet` declaration is collected.

    ## Complete minimal example

    ```js
    Vela.configure({
      launcher: { applicationSearch: true },
      clipboard: { limit: 200, ignoredBundleIdentifiers: ["com.1password.1password"] },
      switcher: { includeMinimizedWindows: false },
      contextSnippets: [{
        name: "Office address",
        description: "Billing, shipping, or office-address input fields",
        content: "〒123-4567\\n東京都…",
      }],
    });

    Vela.hotkey("command+shift+space", Vela.showLauncher);
    Vela.hotkey("command+shift+v", Vela.showClipboard);
    Vela.hotkey("option+[", () => Vela.window("leftHalf"));

    Vela.command({
      id: "open-workspace",
      title: "Open workspace",
      subtitle: "Open it in Finder",
      keywords: ["project", "code"],
      run: () => Vela.shell("open ~/workspace"),
    });

    Vela.search({
      keyword: "g",
      title: "Google",
      url: "https://www.google.com/search?q={query}",
    });

    Vela.snippet({
      id: "reply-thanks",
      title: "Thanks",
      group: "Replies",
      value: "Thank you for your message.",
      keywords: ["reply", "thanks"],
    });
    ```

    ## `Vela.configure(object)`

    All properties are optional. Omitted properties retain their existing/default value. Values and property names are decoded strictly; an unknown property is an error rather than being ignored.

    | Property | Shape | Default | Meaning |
    | --- | --- | --- | --- |
    | `launcher` | `{ applicationSearch: boolean }` | `true` | Include installed applications in launcher search. |
    | `clipboard` | `{ limit: number, ignoredBundleIdentifiers: string[] }` | `200`, `[]` | Entries to retain and bundle IDs whose copies are excluded. `limit` must be an integer from 1 to 10,000. |
    | `switcher` | `{ includeMinimizedWindows: boolean }` | `false` | Include minimized windows in the window switcher. |
    | `contextSnippets` | `ContextSnippet[]` | `[]` | Candidates ranked from the focused input field's accessible context. |

    Each `ContextSnippet` has non-empty, unique `name`, `description`, and `content`:

    ```js
    { name: "Company address", description: "Billing or shipping address fields", content: "〒123-4567\\n東京都…" }
    ```

    Vela sends only each context snippet's `name` and `description` to Apple's Private Cloud Compute (PCC); it never sends a focused field's current value or a snippet's `content`. PCC requires Apple's managed entitlement and falls back to local deterministic ordering when unavailable. Secure text fields are excluded; a user must still press Enter or click to paste.

    ## `Vela.hotkey(keys, action)`

    `keys` is a `+`-separated string such as `"command+shift+space"`. It must contain at least one modifier and exactly one primary key. Empty parts and repeated modifiers are errors. Use each combination only once; modifier aliases (`cmd`/`command`, `alt`/`option`, `ctrl`/`control`), order, and letter case do not make it distinct.
    Supported primary keys are `a` through `z`, `0` through `9`, `space`, `tab`, `return`, `escape`, `[`, `]`, and the four arrow names `left`, `right`, `up`, and `down`.

    ```js
    Vela.hotkey("option+f", Vela.showLauncher);
    Vela.hotkey("command+shift+v", Vela.showClipboard);
    Vela.hotkey("option+tab", Vela.showSwitcher);
    Vela.hotkey("control+option+space", Vela.showContextSnippets);
    Vela.hotkey("control+option+o", Vela.captureTextFromScreen);
    Vela.hotkey("option+shift+q", Vela.quitFrontmostApplication);
    Vela.hotkey("option+[", () => Vela.window("leftHalf"));
    Vela.hotkey("option+]", () => Vela.window("rightHalf"));
    Vela.hotkey("option+m", () => Vela.window("toggleMaximize"));
    Vela.hotkey("option+n", () => Vela.window("minimize"));
    Vela.hotkey("option+q", () => Vela.window("close"));
    Vela.hotkey("option+j", () => Vela.window("nextDisplay"));
    Vela.hotkey("option+k", () => Vela.window("previousDisplay"));
    Vela.hotkey("control+tab", () => Vela.window("focusPrevious"));
    ```

    Supported `Vela.window` names are exactly: `leftHalf`, `rightHalf`, `toggleMaximize`, `minimize`, `close`, `nextDisplay`, `previousDisplay`, and `focusPrevious`.

    ## `Vela.command(object)`

    Commands appear in the launcher. `id`, `title`, and `run` are required; `id` must be unique and `run` must return an action.

    ```js
    Vela.command({
      id: "open-calendar",
      title: "Open Calendar",
      subtitle: "macOS Calendar",
      keywords: ["schedule", "events"],
      run: () => Vela.application("com.apple.iCal"),
    });
    ```

    Available actions:

    ```js
    run: () => Vela.shell("open ~/workspace")       // runs /bin/zsh -lc later
    run: () => Vela.openURL("https://example.com")  // opens a URL with macOS
    run: () => Vela.application("com.apple.iCal")   // opens by bundle identifier
    ```

    `subtitle` and `keywords` are optional; use a string and an array of strings.

    ## `Vela.search(object)`

    A search appears when the launcher input begins with its `keyword` followed by
    whitespace and a non-empty query. Enter opens `url` after Vela percent-encodes
    the query and substitutes it for exactly one `{query}` placeholder. `keyword`
    must be a single non-blank token and unique without regard to case; `title` is optional and defaults to
    `"Search"`.

    ```js
    // Type: g Swift URL
    Vela.search({
      keyword: "g",
      title: "Google",
      subtitle: "Search the web",
      url: "https://www.google.com/search?q={query}",
    });
    ```

    ## `Vela.snippet(object)`

    Snippets are fixed text selected from the palette. `id`, `title`, and `value` must be non-empty, and `id` must be unique.

    ```js
    Vela.snippet({
      id: "email-signature",
      title: "Email signature",
      group: "Work",
      value: "Name\\nCompany",
      keywords: ["signature", "email"],
    });
    ```

    `group` and `keywords` are optional. Use `group` to create meaningful browsing clusters, not as a substitute for a clear title.

    ## CLI workflow

    ```sh
    vela doctor       # show the active configuration path
    vela open         # open the active configuration directory in Finder
    vela check        # parse and validate the active vela.js
    vela reload       # wait for the running Vela app to accept the configuration
    ```

    `vela init` creates missing starter files but preserves an existing `vela.js` and skill documentation.
    """
}
