# Installer verification — 2026-09-22

Local candidate: `dist/0.3.9/Vela-0.3.9.dmg`, app version 0.3.9, build 12.
This candidate has not been published to GitHub Releases.

## Verified

- 20 Swift unit tests pass; release build and app bundle build pass without
  compiler warnings. Embedded CLI usage exits successfully.
- Finder displays the app, Applications shortcut, arrow, and instruction in
  the 560 × 360 installer layout. Older mounted installers do not supply its
  background; the volume name contains the version and metadata is regenerated.
- The Applications shortcut resolves to `/Applications`.
- Opening the read-only installer app copies it to `/Applications/Vela.app`,
  exits the disk-image process, and launches the installed app with setup visible.
  Source and installed executable SHA-256 values match. Strict signature
  verification passes after copying.
- Native setup welcome/completion, AI selection, back navigation, and clipboard
  handoff display correctly. The clipboard handoff contains the installed CLI
  path and the initialization instruction.
- Dragging the installed setup window's title bar changed its saved frame from
  `0 420 520 428` to `0 495 520 428`; selection and handoff pages kept that frame.
- The installed app responds to `vela doctor` and `vela permissions status`.
- Finder copy/paste through an Applications-style symlink to an isolated test
  folder succeeds and preserves the executable hash and strict signature.
- The originally installed Vela was restored and relaunched after testing.

## Apple notarization

- App/archive submission: `f95bd5d3-3d71-4a5e-8e85-8915dcfc0f39`, Accepted.
- DMG submission: `45798cd4-aa81-418b-8bac-a96e664cb92d`, Accepted.
- Stapler validation succeeds for both the DMG and the app mounted from it.
- Gatekeeper accepts both with `source=Notarized Developer ID`.
- DMG SHA-256: `859d8ea8ef902c7f87c3102c36844e4f26d1acbe1b2bbd3af725e855efcaf45e`.

## Remaining manual check

The computer-use drag gesture selected the destination without beginning a
copy, including in an isolated fixture. Copy/paste to the same destination
worked. Direct drag-and-drop copying is therefore still awaiting user
confirmation; it is not counted as a passed interaction test.

After the Mac was unlocked, the same automated gesture also failed to move an
ordinary text file into an ordinary folder on the writable local disk. This
control test reproduced the limitation without a DMG, app bundle, or symlink.
