# Notarized releases

Pushing a commit to `main` runs `.github/workflows/notarized-release.yml`. The
workflow chooses the next patch version from the highest `vMAJOR.MINOR.PATCH`
tag, signs the app and embedded `vela` helper, notarizes and staples the app
and DMG, verifies both with Gatekeeper, then publishes the versioned DMG, a
same-byte `Vela-latest.dmg` alias, arm64 tarball, and `SHA256SUMS` as a GitHub
Release. The stable latest-download URL is:

```text
https://github.com/tubasasakunn/vela/releases/latest/download/Vela-latest.dmg
```

Re-running a successful or partially successful run for the same commit reuses
that commit's existing release tag and replaces its assets. Releases are
serialized, so two `main` pushes cannot choose the same next version. Use
**Run workflow** with the optional `version` input only to select an explicit
`MAJOR.MINOR.PATCH` version.

## One-time GitHub setup

Add these repository Actions secrets. Do not commit certificates or keys.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 of a `.p12` export containing the **Developer ID Application** certificate and private key. |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used when exporting that `.p12`. |
| `RELEASE_KEYCHAIN_PASSWORD` | A new random password used only for the runner's temporary keychain. |
| `ASC_KEY_ID` | Key ID of a team-scoped App Store Connect API key permitted to use `notarytool`. |
| `ASC_ISSUER_ID` | Issuer ID for that API key. |
| `ASC_KEY_CONTENT` | Base64 of the API key's `.p8` file. |

Create the two Base64 values on a trusted Mac without copying either source
file into the repository:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

The workflow imports the certificate into an ephemeral runner keychain and
deletes that keychain at the end of every run. It passes the App Store Connect
key directly to `xcrun notarytool` through the existing release script; the
script writes it only to a temporary file and removes it on exit.

## Release evidence

`Scripts/build-dmg.sh <Vela.app> <output.dmg>` builds the same Finder layout
locally without notarizing or publishing. It installs the pinned packaging tools
from `Scripts/dmg-requirements.txt` into `.build/dmg-tools`. The background alias
is generated on each new volume, and the volume name includes the app version
so an older mounted installer cannot supply the artwork.
`Scripts/dmg-settings.py` defines the initial window size and icon
positions; the Finder window remains movable and resizable.

Before release, open the image in Finder and confirm both icons, the drag arrow,
and the instruction are visible. Drag Vela onto Applications and launch the
installed copy; check setup navigation and that its title bar can be dragged.

The job fails unless Apple accepts each notarization, `xcrun stapler validate`
succeeds, and `spctl` identifies the stapled app and DMG as acceptable. The
published `SHA256SUMS` includes checksums for the versioned DMG, latest DMG
alias, and arm64 tarball.
