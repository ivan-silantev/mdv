class Mdv < Formula
  desc "Markdown renderer CLI in the terminal"
  homepage "https://github.com/ivan-silantev/mdv"
  version "0.1.2"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-macos-aarch64.tar.gz"
      sha256 "a876db0d2f8a54130564dcdd47a666d272e1083f0eed98482642e048a165038e"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-macos-x86_64.tar.gz"
      sha256 "30937237f9de0bccc0accde874d17a85b72346f3b6782f7f601616718d9e9555"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-linux-aarch64.tar.gz"
      sha256 "93608b36e48028714af8a4361ce0dd511ae47067f186b2cde20c38546d9d70e9"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-linux-x86_64.tar.gz"
      sha256 "096a2e14bdf9a1e66b777c2c412765b195493e6087712d7638370eb134112522"
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
