# Template. The live copy belongs in the tap repo skdev24/homebrew-jot at Casks/jot.rb.
# Per release: set version + sha256 (printed by scripts/release.sh and the Release workflow).
cask "jot" do
  version "2.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/skdev24/jot/releases/download/v#{version}/Jot-#{version}.zip"
  name "Jot"
  desc "Notes that live in the notch"
  homepage "https://github.com/skdev24/jot"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle updates the app in place.
  auto_updates true
  depends_on macos: ">= :sequoia"

  app "Jot.app"

  uninstall quit: "com.shivam.jot"

  # Notes in ~/Documents/Jot are user data and are deliberately left alone.
  zap trash: [
    "~/Library/Application Support/com.shivam.jot",
    "~/Library/Caches/com.shivam.jot",
    "~/Library/HTTPStorages/com.shivam.jot",
    "~/Library/Preferences/com.shivam.jot.plist",
    "~/Library/Saved Application State/com.shivam.jot.savedState",
    "~/Library/WebKit/com.shivam.jot",
  ]
end
