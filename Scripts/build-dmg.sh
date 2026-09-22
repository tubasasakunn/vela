#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
if [[ $# != 2 ]]; then
  echo "Usage: $0 <Vela.app> <output.dmg>" >&2
  exit 64
fi
app_path="${1:A}"
dmg_path="${2:A}"
[[ -x "$app_path/Contents/MacOS/Vela" ]] || { echo "Invalid app: $app_path" >&2; exit 1; }
codesign --verify --deep --strict "$app_path"
[[ ! -e "$dmg_path" ]] || { echo "Output already exists: $dmg_path" >&2; exit 1; }
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"

tools_dir="$project_dir/.build/dmg-tools"
if [[ ! -x "$tools_dir/bin/python" ]]; then
  python3 -m venv "$tools_dir"
fi
"$tools_dir/bin/python" -m pip --disable-pip-version-check install --quiet -r "$script_dir/dmg-requirements.txt"
layout_dir="$(mktemp -d /tmp/vela-dmg-artwork.XXXXXX)"
image_mounted=0
cleanup() {
  if (( image_mounted )); then
    hdiutil detach -quiet "$layout_dir/mounted" || return
  fi
  if [[ "$layout_dir" == /tmp/vela-dmg-artwork.* && -d "$layout_dir" ]]; then
    /bin/rm -r -- "$layout_dir"
  fi
}
trap cleanup EXIT
sips -s format tiff "$project_dir/Resources/VelaDMGBackground.svg" --out "$layout_dir/background.tiff" >/dev/null
"$tools_dir/bin/dmgbuild" -s "$script_dir/dmg-settings.py" \
  -D app="$app_path" -D background="$layout_dir/background.tiff" \
  "Vela $version" "$layout_dir/Vela.dmg"

# Finder layout tools must not invalidate the already-signed app's metadata.
mkdir "$layout_dir/mounted"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$layout_dir/mounted" "$layout_dir/Vela.dmg"
image_mounted=1
codesign --verify --deep --strict "$layout_dir/mounted/${app_path:t}"
[[ "$(readlink "$layout_dir/mounted/Applications")" == /Applications ]]
hdiutil detach -quiet "$layout_dir/mounted"
image_mounted=0
mkdir -p "${dmg_path:h}"
ditto "$layout_dir/Vela.dmg" "$dmg_path"
