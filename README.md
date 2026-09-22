# Vela

Vela is a native macOS utility that combines a launcher, clipboard history,
global hotkeys, window movement, and a window switcher. It has no settings
screen: its behavior lives in one JavaScript file that can be committed to Git.

## Install

Install the Apple-notarized release directly from the Formula. Homebrew resolves
the repository-qualified name without a separate `brew tap` step:

```sh
brew install tubasasakunn/tap/vela
vela init
```

The Formula installs a prebuilt Developer ID-signed and Apple-notarized app, so
it does not compile Swift during installation. `vela init` lets you choose
where to create `vela.js`, then guides you through the permissions Vela needs.
Existing configuration is kept unchanged.

To install the app without Homebrew, download the notarized DMG from the latest
[GitHub release](https://github.com/tubasasakunn/vela/releases/latest) and drag
Vela to Applications.

For development, build it locally:

```sh
git clone git@github.com:tubasasakunn/vela.git
cd vela
./Scripts/install-local.sh
open -a Vela
```

## Configuration

`vela init` creates `~/.config/vela/vela.js`. It is normal JavaScript running
against a small, documented Vela API; it is not a custom language. The config
is evaluated only to describe actions. It has no filesystem, network, or
environment access while loading.

The selected configuration directory also receives `AGENT.md` and
`.agent/skills/vela-configuration/`. Together, they tell an AI agent about
Vela's capabilities, require it to confirm the intended setup with the user,
and provide the supported settings, constraints, and examples needed to safely
create or edit `vela.js`. Later `vela init` runs preserve any edits to these
files.

For an LLM-readable installation and configuration sequence, use
[vela.basaapp.com/setup.md](https://vela.basaapp.com/setup.md). The concise
LLM index is available at [vela.basaapp.com/llm.txt](https://vela.basaapp.com/llm.txt).

```js
Vela.configure({
  clipboard: {
    limit: 200,
    ignoredBundleIdentifiers: ["com.1password.1password"],
  },
});

Vela.hotkey("command+shift+space", Vela.showLauncher);
Vela.hotkey("option+f", Vela.showLauncher);
Vela.hotkey("command+shift+v", Vela.showClipboard);
// Select a screen area; recognized text is copied to the clipboard.
Vela.hotkey("control+option+o", Vela.captureTextFromScreen);
Vela.hotkey("option+tab", Vela.showSwitcher);
Vela.hotkey("command+option+left", () => Vela.window("leftHalf"));

Vela.command({
  id: "open-workspace",
  title: "Open workspace",
  keywords: ["project", "code"],
  run: () => Vela.shell("open ~/workspace"),
});

// Type `g Swift URL` in the launcher, then press Enter.
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
  keywords: ["reply"],
});

// On macOS 27+ with PCC available, Vela sends only each candidate's name and
// description to Apple's Private Cloud Compute to choose the best candidate.
// The configured content remains local and is resolved only after PCC returns
// a candidate name.
Vela.configure({
  contextSnippets: [
    {
      name: "Company address",
      description: "Billing, shipping, or office-address input fields",
      content: "〒123-4567\n東京都…",
    },
  ],
});
Vela.hotkey("control+option+space", Vela.showContextSnippets);
```

Vela never sends a field's current value or a candidate's content to PCC.
Password and other secure text fields are excluded. The palette always
requires Enter/click to paste; if PCC is unavailable, candidates remain
available in their configured order.

PCC requires Apple's managed `com.apple.developer.private-cloud-compute`
entitlement. Set `VELA_ENABLE_PCC=1` only for a release signing identity that
Apple has approved for this capability; local builds omit it and use the
deterministic ranking fallback.

### API

- `Vela.configure({ launcher, clipboard, switcher, contextSnippets })`
- `Vela.hotkey("command+shift+space", Vela.showLauncher)`
- `Vela.hotkey(keys, Vela.showClipboard | Vela.showSwitcher | Vela.captureTextFromScreen | Vela.quitFrontmostApplication)`
- `Vela.hotkey(keys, Vela.showContextSnippets)`
- `Vela.hotkey(keys, () => Vela.window("leftHalf" | "rightHalf" | "toggleMaximize" | "minimize" | "close" | "nextDisplay" | "previousDisplay" | "focusPrevious"))`
- `Vela.command({ id, title, subtitle?, keywords?, run })`
- `Vela.search({ keyword, title?, subtitle?, url })`
- `Vela.snippet({ id, title, value, group?, keywords? })`
- command actions: `Vela.shell(command)`, `Vela.openURL(url)`, and
  `Vela.application(bundleIdentifier)`

## CLI

```sh
vela init
vela check
vela reload
vela doctor
vela open
vela show search
vela show clipboard
vela show context
vela run open-workspace
vela clipboard list
vela snippets import-clipy
vela permissions status
vela permissions setup
vela permissions request accessibility
vela permissions open accessibility
```

`vela check` validates the JavaScript API result, hotkey collisions, command
IDs, and clipboard bounds before the running application adopts it.

## Permissions

Vela has no permission settings screen. Configure access with the interactive
CLI instead:

```sh
vela permissions setup
```

The CLI shows an animated checklist, watches macOS for permission changes, and
advances automatically. It never asks again for access that is already granted.
If macOS no longer shows a prompt, open the matching page explicitly with
`vela permissions open <name>`. `vela permissions request all` is an alias for
the guided flow.

## Development

```sh
swift test
./Scripts/build-app.sh
open Vela.app
```

The app requires macOS 14 or later. On macOS 26 and later, its command surface
uses the native Liquid Glass effect. Earlier supported systems use the matching
system material fallback.
