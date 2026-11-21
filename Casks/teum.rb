cask "teum" do
  version "0.3.0"
  sha256 "fe7106d873136bea5ab20cbd26e29c50b734d5e557c0f207dcb5e3d50e01fc27"

  url "https://github.com/lee-jonny/teum-note/releases/download/v#{version}/Teum-#{version}-macos-arm64.zip"
  name "Teum"
  desc "Markdown notes at the edge of the screen"
  homepage "https://github.com/lee-jonny/teum-note"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Teum.app"
end
