class Mdv < Formula
  desc "Markdown renderer CLI in the terminal"
  homepage "https://github.com/ivan-silantev/mdv"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v#{version}/mdv-macos-aarch64.tar.gz"
      sha256 "8e266b3c8e5d30c9b9c6c01390b95bd4aa3b3241f337cd9fb5cae70600ee7c5b"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v#{version}/mdv-macos-x86_64.tar.gz"
      sha256 "eedda6c229fe7765db51b270ba2f839dee97f7423e724651f8bdbd985f6de424"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v#{version}/mdv-linux-aarch64.tar.gz"
      sha256 "3fd28b79eea164e2d00f7aaece45e9331482657a35632496b2a74a5fbb7db119"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v#{version}/mdv-linux-x86_64.tar.gz"
      sha256 "c7bed1de554dff9135097fc062fa6627a7f799a8839735ce426a5722929b9d26"
    end
  end

  def install
    bin.install "mdv"
  end

  test do
    (testpath/"sample.md").write("# Hello\n\n**world**\n")
    assert_match "Hello", shell_output("#{bin}/mdv #{testpath}/sample.md")
    assert_match "<h1>Hello</h1>", shell_output("#{bin}/mdv --html #{testpath}/sample.md")
  end
end
