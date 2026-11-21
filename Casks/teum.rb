cask "teum" do
  version "0.5.0"
  sha256 "cc2fa7fd6c655dfd39182bb45b8855934b895d4a3ccd09b0b113dbcc246ecd2a"

  url "https://github.com/lee-jonny/teum-note/releases/download/v#{version}/Teum-#{version}-macos-arm64.zip"
  name "Teum"
  desc "Markdown notes at the edge of the screen"
  homepage "https://github.com/lee-jonny/teum-note"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Teum.app"
end
