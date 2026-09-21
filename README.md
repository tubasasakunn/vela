# Vela

Vela is a native macOS utility that combines a launcher, clipboard history,
global hotkeys, window movement, and a window switcher. It has no settings
screen: its behavior lives in one JavaScript file that can be committed to Git.

## Install

Install the Formula:

```sh
brew tap tubasasakunn/tap
HOMEBREW_NO_SANDBOX=1 brew install vela
brew services start vela
vela init
```

`HOMEBREW_NO_SANDBOX=1` is required on hosts where SwiftPM cannot use
macOS's legacy `sandbox-exec` facility.

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

```js
Vela.configure({
  clipboard: {
    limit: 200,
    ignoredBundleIdentifiers: ["com.1password.1password"],
  },
});

Vela.hotkey("command+shift+space", Vela.showLauncher);
Vela.hotkey("command+shift+v", Vela.showClipboard);
Vela.hotkey("command+option+left", () => Vela.window("leftHalf"));

Vela.command({
  id: "open-workspace",
  title: "Open workspace",
  keywords: ["project", "code"],
  run: () => Vela.shell("open ~/workspace"),
});
```

### API

- `Vela.configure({ launcher, clipboard, switcher })`
- `Vela.hotkey("command+shift+space", Vela.showLauncher)`
- `Vela.hotkey(keys, Vela.showClipboard | Vela.showSwitcher | Vela.quitFrontmostApplication)`
- `Vela.hotkey(keys, () => Vela.window("leftHalf" | "rightHalf" | "toggleMaximize" | "minimize" | "close" | "nextDisplay" | "previousDisplay" | "focusPrevious"))`
- `Vela.command({ id, title, subtitle?, keywords?, run })`
- command actions: `Vela.shell(command)`, `Vela.openURL(url)`, and
  `Vela.application(bundleIdentifier)`

## CLI

```sh
vela init
vela check
vela reload
vela doctor
vela open
vela run open-workspace
vela clipboard list
```

`vela check` validates the JavaScript API result, hotkey collisions, command
IDs, and clipboard bounds before the running application adopts it.

## Permissions

Vela runs as a menu-bar app. On first launch, it presents one clear checklist
for Accessibility, Input Monitoring, Screen Recording, and Notifications, then
asks for each permission in a deliberate order. You can reopen the checklist
from the Vela menu at any time.

## Development

```sh
swift test
./Scripts/build-app.sh
open Vela.app
```

The app requires macOS 14 or later. On macOS 26 and later, its command surface
uses the native Liquid Glass effect. Earlier supported systems use the matching
system material fallback.
