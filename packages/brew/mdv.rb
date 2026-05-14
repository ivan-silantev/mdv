class Mdv < Formula
  desc "Markdown renderer CLI in the terminal"
  homepage "https://github.com/ivan-silantev/mdv"
  url "https://github.com/ivan-silantev/mdv.git", tag: "v0.1.0"
  license "MIT"

  depends_on "zig@0.15" => :build

  def install
    system Formula["zig@0.15"].opt_bin/"zig", "build", "-Doptimize=ReleaseSafe", "--prefix", prefix
  end

  test do
    (testpath/"sample.md").write("# Hello\n\n**world**\n")
    assert_match "Hello", shell_output("#{bin}/mdv #{testpath}/sample.md")
    assert_match "<h1>Hello</h1>", shell_output("#{bin}/mdv --html #{testpath}/sample.md")
  end
end
