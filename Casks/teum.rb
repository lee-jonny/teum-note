cask "teum" do
  version "0.2.0"
  sha256 "7bfad797d7fa02f6d33ba8a2e742857e1c534a7eb0b40cf1fe11be1112dfdc29"

  url "https://github.com/lee-jonny/teum-note/releases/download/v#{version}/Teum-#{version}-macos-arm64.zip"
  name "Teum"
  desc "Markdown notes at the edge of the screen"
  homepage "https://github.com/lee-jonny/teum-note"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Teum.app"
end
