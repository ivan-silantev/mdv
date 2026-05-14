class Mdv < Formula
  desc "Markdown renderer CLI in the terminal"
  homepage "https://github.com/ivan-silantev/mdv"
  version "0.1.1"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.1/mdv-macos-aarch64.tar.gz"
      sha256 "9f506d36f022ff6227f39f782d37f64b89fe489eed47b71c056233d4131120ee"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.1/mdv-macos-x86_64.tar.gz"
      sha256 "06be246b8b6911976070e25cb32b749acf54dd38f05d588be6643f1f63a01170"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.1/mdv-linux-aarch64.tar.gz"
      sha256 "2c7ecc9f8355101f84cbb4d3a407d575a0e7e089f40715c37fe4b4a01921a3ce"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.1/mdv-linux-x86_64.tar.gz"
      sha256 "cc0e1110b02839ecdc62a905d1337707a0cb85e11070a661698db5289d9ebe89"
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
