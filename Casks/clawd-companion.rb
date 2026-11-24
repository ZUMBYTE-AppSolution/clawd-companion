cask "clawd-companion" do
  version "0.7.3"
  sha256 "3de754d532a6e44b354ebac805c159195d1bd03134e44e9be1566b98286f5fad"

  url "https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v#{version}/Clawd-Companion-#{version}-macOS-universal.zip"
  name "Claw’d Companion"
  desc "Animated pixel desktop companion for Claude"
  homepage "https://github.com/ZUMBYTE-AppSolution/clawd-companion"

  depends_on macos: ">= :ventura"
  app "Clawd Companion.app"
end
