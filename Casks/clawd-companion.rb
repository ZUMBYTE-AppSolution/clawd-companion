cask "clawd-companion" do
  version "0.7.1"
  sha256 "8fac26668703442c6ff34b8fc88075173186f0b7c4ca788a3e8fa4386730857d"

  url "https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v#{version}/Clawd-Companion-#{version}-macOS-universal.zip"
  name "Claw’d Companion"
  desc "Animated pixel desktop companion for Claude"
  homepage "https://github.com/ZUMBYTE-AppSolution/clawd-companion"

  depends_on macos: ">= :ventura"
  app "Clawd Companion.app"
end
