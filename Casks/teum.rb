cask "teum" do
  version "0.4.0"
  sha256 "229e9deba9cc6cc43641fae937492fedb47e2ac6a607dab467b1bf33336f2b54"

  url "https://github.com/lee-jonny/teum-note/releases/download/v#{version}/Teum-#{version}-macos-arm64.zip"
  name "Teum"
  desc "Markdown notes at the edge of the screen"
  homepage "https://github.com/lee-jonny/teum-note"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Teum.app"
end
