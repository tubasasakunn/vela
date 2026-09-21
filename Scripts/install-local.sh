#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
"$script_dir/build-app.sh"
rm -rf /Applications/Vela.app
ditto "$project_dir/Vela.app" /Applications/Vela.app
swift build --configuration release --product vela --package-path "$project_dir"
mkdir -p "$HOME/.local/bin"
ln -sf "$project_dir/.build/release/vela" "$HOME/.local/bin/vela"
echo "Installed Vela.app and ~/.local/bin/vela"
