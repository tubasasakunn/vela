#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
build_dir="${project_dir}/.build/release"
app_dir="${project_dir}/Vela.app"

cd "$project_dir"
swift build --configuration release --product VelaApp
swift build --configuration release --product vela
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Helpers"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp Resources/VelaMenuBarIcon.svg "$app_dir/Contents/Resources/VelaMenuBarIcon.svg"
cp "$build_dir/VelaApp" "$app_dir/Contents/MacOS/Vela"
cp "$build_dir/vela" "$app_dir/Contents/Helpers/vela"
if [[ -n "${VELA_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VELA_VERSION" "$app_dir/Contents/Info.plist"
fi
if [[ -n "${VELA_BUILD_NUMBER:-}" ]]; then
  plutil -replace CFBundleVersion -string "$VELA_BUILD_NUMBER" "$app_dir/Contents/Info.plist"
fi
# Keep the same designated requirement as the distributed app so macOS privacy
# grants remain attached to Vela after a local development install.
signing_identity="${VELA_SIGNING_IDENTITY:-Developer ID Application: BasaApp Technologies (7NN5KD3TSU)}"
codesign --force --options runtime --timestamp --sign "$signing_identity" \
  "$app_dir/Contents/Helpers/vela"
pcc_entitlements=()
if [[ "${VELA_ENABLE_PCC:-0}" == "1" ]]; then
  pcc_entitlements=(--entitlements Resources/Vela.entitlements)
fi
codesign --force --options runtime --timestamp "${pcc_entitlements[@]}" \
  --sign "$signing_identity" "$app_dir"
echo "Built $app_dir"
