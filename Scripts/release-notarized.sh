#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
version="${1:-}"
build_number="${2:-}"

if [[ -z "$version" || -z "$build_number" ]]; then
  echo "Usage: $0 <version> <build-number>" >&2
  exit 64
fi

for name in ASC_KEY_ID ASC_ISSUER_ID; do
  if [[ -z "${(P)name:-}" ]]; then
    echo "$name is required" >&2
    exit 64
  fi
done
if [[ -z "${ASC_KEY_PATH:-}" && -z "${ASC_KEY_CONTENT:-}" && -z "${ASC_PRIVATE_KEY:-}" ]]; then
  echo "ASC_KEY_PATH or ASC_KEY_CONTENT is required" >&2
  exit 64
fi

release_dir="${project_dir}/dist/${version}"
work_dir="$(mktemp -d /tmp/vela-release.XXXXXX)"
cleanup() {
  if [[ "$work_dir" == /tmp/vela-release.* && -d "$work_dir" ]]; then
    trash "$work_dir" 2>/dev/null || /bin/rm -rf "$work_dir"
  fi
}
trap cleanup EXIT

key_path="${ASC_KEY_PATH:-}"
if [[ -z "$key_path" ]]; then
  key_path="$work_dir/AuthKey_${ASC_KEY_ID}.p8"
  key_content="${ASC_KEY_CONTENT:-${ASC_PRIVATE_KEY:-}}"
  KEY_CONTENT="$key_content" KEY_PATH="$key_path" python3 - <<'PY'
import base64
import os
from pathlib import Path

raw = os.environ["KEY_CONTENT"].strip().strip('"').strip("'")
if "BEGIN PRIVATE KEY" not in raw:
    raw = base64.b64decode(raw).decode()
raw = raw.replace("\\n", "\n")
path = Path(os.environ["KEY_PATH"])
path.write_text(raw)
path.chmod(0o600)
PY
fi

mkdir -p "$release_dir" "$work_dir/archive" "$work_dir/dmg"

cd "$project_dir"
VELA_VERSION="$version" VELA_BUILD_NUMBER="$build_number" "$script_dir/build-app.sh"
codesign --verify --deep --strict --verbose=2 Vela.app

ditto Vela.app "$work_dir/archive/Vela.app"
cp .build/release/vela "$work_dir/archive/vela"
codesign --force --options runtime --timestamp \
  --sign "${VELA_SIGNING_IDENTITY:-Developer ID Application: BasaApp Technologies (7NN5KD3TSU)}" \
  "$work_dir/archive/vela"

notary_zip="$work_dir/vela-${version}-notarization.zip"
ditto -c -k --sequesterRsrc "$work_dir/archive" "$notary_zip"
xcrun notarytool submit "$notary_zip" \
  --key "$key_path" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait

xcrun stapler staple "$work_dir/archive/Vela.app"
xcrun stapler validate "$work_dir/archive/Vela.app"
spctl --assess --type execute --verbose=4 "$work_dir/archive/Vela.app"

archive_path="$release_dir/vela-${version}-darwin-arm64.tar.gz"
COPYFILE_DISABLE=1 tar -C "$work_dir/archive" -czf "$archive_path" Vela.app vela

dmg_path="$release_dir/Vela-${version}.dmg"
# Generate Finder metadata against this image's own volume and background.
# A saved .DS_Store can resolve its alias to an older mounted installer.
zsh "$script_dir/build-dmg.sh" "$work_dir/archive/Vela.app" "$work_dir/Vela.dmg"
ditto "$work_dir/Vela.dmg" "$dmg_path"
codesign --force --timestamp \
  --sign "${VELA_SIGNING_IDENTITY:-Developer ID Application: BasaApp Technologies (7NN5KD3TSU)}" \
  "$dmg_path"
xcrun notarytool submit "$dmg_path" \
  --key "$key_path" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

shasum -a 256 "$archive_path" "$dmg_path" | tee "$release_dir/SHA256SUMS"
echo "Notarized release artifacts are in $release_dir"
