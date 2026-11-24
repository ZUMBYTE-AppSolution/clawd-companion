cask "clawd-companion" do
  version "0.6.1"
  sha256 "a19038331d5c84641c9e779c19fc836aaac64e35dbefc9d56bdd143d5c2408e7"

  url "https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v#{version}/Clawd-Companion-#{version}-macOS-universal.zip"
  name "Claw’d Companion"
  desc "Animated pixel desktop companion for Claude"
  homepage "https://github.com/ZUMBYTE-AppSolution/clawd-companion"

  depends_on macos: ">= :ventura"
  app "Clawd Companion.app"
end
