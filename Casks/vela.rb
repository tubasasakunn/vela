cask "vela" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/tubasasakunn/vela/releases/download/v#{version}/Vela.zip",
      verified: "github.com/tubasasakunn/vela/"
  name "Vela"
  desc "File-configured launcher, clipboard, hotkey, and window utility"
  homepage "https://github.com/tubasasakunn/vela"

  depends_on macos: ">= :sonoma"

  app "Vela.app"
  binary "Vela.app/Contents/Helpers/vela", target: "vela"

  zap trash: [
    "~/Library/Application Support/Vela",
    "~/.config/vela",
  ]
end
