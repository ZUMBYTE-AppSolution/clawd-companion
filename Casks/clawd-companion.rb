cask "clawd-companion" do
  version "0.6.0"
  sha256 "bf351322ef81fc72fbc139cacd4c6c7752c18823ce9db1b6fee6df3025a54b7c"

  url "https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v#{version}/Clawd-Companion-#{version}-macOS-universal.zip"
  name "Claw’d Companion"
  desc "Animated pixel desktop companion for Claude"
  homepage "https://github.com/ZUMBYTE-AppSolution/clawd-companion"

  depends_on macos: ">= :ventura"
  app "Clawd Companion.app"
end
