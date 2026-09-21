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
cp "$build_dir/VelaApp" "$app_dir/Contents/MacOS/Vela"
cp "$build_dir/vela" "$app_dir/Contents/Helpers/vela"
codesign --force --sign - "$app_dir"
echo "Built $app_dir"
