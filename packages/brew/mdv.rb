class Mdv < Formula
  desc "Markdown renderer CLI in the terminal"
  homepage "https://github.com/ivan-silantev/mdv"
  version "0.1.2"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-macos-aarch64.tar.gz"
      sha256 "8d38bd972159a6249f97b24693eb37e7c5718e64479d32e29ea5c1a30a538ae5"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-macos-x86_64.tar.gz"
      sha256 "bf8e25765969c7f63d1cc71808396827be4e50745018fc76b2c1d5859422ec5e"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-linux-aarch64.tar.gz"
      sha256 "686d708bad5c425ecd0a2418fdbc026bc32dd6f180493567c87bf614ad8512f3"
    else
      url "https://github.com/ivan-silantev/mdv/releases/download/v0.1.2/mdv-linux-x86_64.tar.gz"
      sha256 "f806bf99d4492621e9ad530d66afd17852b2bc0d193d7951c165cfe80f642775"
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
