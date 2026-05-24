#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/release.sh VERSION [--publish] [--draft]

Examples:
  tools/release.sh 0.1.1
  tools/release.sh 0.1.1 --publish
  tools/release.sh 0.1.1 --publish --draft

This script:
  - builds release artifacts for macOS, Linux, and Windows
  - computes SHA-256 checksums
  - updates package manifests to the requested version
  - optionally creates or updates a GitHub release and uploads artifacts via gh CLI
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

version=""
publish=0
draft=0

for arg in "$@"; do
  case "$arg" in
    --publish)
      publish=1
      ;;
    --draft)
      draft=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$version" ]]; then
        version="$arg"
      else
        echo "Unexpected argument: $arg" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$version" ]]; then
  echo "VERSION is required" >&2
  usage
  exit 1
fi

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must look like 0.1.1" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

zig_bin="${ZIG_BIN:-}"
if [[ -z "$zig_bin" ]]; then
  if command -v zig >/dev/null 2>&1; then
    zig_bin="$(command -v zig)"
  elif [[ -x /usr/local/bin/zig ]]; then
    zig_bin="/usr/local/bin/zig"
  else
    echo "zig not found. Set ZIG_BIN or install zig 0.16.x." >&2
    exit 1
  fi
fi

zig_version="$($zig_bin version)"
case "$zig_version" in
  0.16.*) ;;
  *)
    echo "zig 0.16.x is required for release builds; found $zig_version at $zig_bin." >&2
    exit 1
    ;;
esac

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required" >&2
  exit 1
fi

release_date="${RELEASE_DATE:-$(date +%F)}"
tag="v${version}"
release_url_base="https://github.com/ivan-silantev/mdv/releases/download/${tag}"

export ZIG_GLOBAL_CACHE_DIR="$repo_root/.zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="$repo_root/.zig-local-cache"
mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR" "$repo_root/dist"

rm -rf "$repo_root/dist/release-assets"
mkdir -p "$repo_root/dist/release-assets"

build_tarball() {
  local zig_target="$1"
  local artifact_name="$2"
  local stage_dir="$repo_root/dist/release-assets/$artifact_name"

  rm -rf "$stage_dir"
  "$zig_bin" build -Dtarget="$zig_target" -Doptimize=ReleaseSafe --prefix "$stage_dir/prefix"
  cp "$stage_dir/prefix/bin/mdv" "$stage_dir/mdv"
  tar -C "$stage_dir" -czf "$repo_root/dist/${artifact_name}.tar.gz" mdv
}

build_windows_zip() {
  local stage_dir="$repo_root/dist/release-assets/mdv-windows-x86_64"

  rm -rf "$stage_dir"
  "$zig_bin" build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe
  mkdir -p "$stage_dir"
  cp "$repo_root/zig-out/bin/mdv.exe" "$stage_dir/mdv.exe"
  (
    cd "$stage_dir"
    zip -9 -X "$repo_root/dist/mdv-windows-x86_64.zip" mdv.exe >/dev/null
  )
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

build_tarball "aarch64-macos" "mdv-macos-aarch64"
build_tarball "x86_64-macos" "mdv-macos-x86_64"
build_tarball "aarch64-linux-musl" "mdv-linux-aarch64"
build_tarball "x86_64-linux-musl" "mdv-linux-x86_64"
build_windows_zip

sha_macos_aarch64="$(sha256_file "$repo_root/dist/mdv-macos-aarch64.tar.gz")"
sha_macos_x86_64="$(sha256_file "$repo_root/dist/mdv-macos-x86_64.tar.gz")"
sha_linux_aarch64="$(sha256_file "$repo_root/dist/mdv-linux-aarch64.tar.gz")"
sha_linux_x86_64="$(sha256_file "$repo_root/dist/mdv-linux-x86_64.tar.gz")"
sha_windows_x86_64="$(sha256_file "$repo_root/dist/mdv-windows-x86_64.zip")"

export MDV_VERSION="$version"
export MDV_TAG="$tag"
export MDV_RELEASE_DATE="$release_date"
export MDV_RELEASE_URL_BASE="$release_url_base"
export MDV_SHA_MACOS_AARCH64="$sha_macos_aarch64"
export MDV_SHA_MACOS_X86_64="$sha_macos_x86_64"
export MDV_SHA_LINUX_AARCH64="$sha_linux_aarch64"
export MDV_SHA_LINUX_X86_64="$sha_linux_x86_64"
export MDV_SHA_WINDOWS_X86_64="$sha_windows_x86_64"

ruby <<'RUBY'
repo_root = Dir.pwd
version = ENV.fetch("MDV_VERSION")
tag = ENV.fetch("MDV_TAG")
release_date = ENV.fetch("MDV_RELEASE_DATE")
release_url_base = ENV.fetch("MDV_RELEASE_URL_BASE")

brew_path = File.join(repo_root, "packages/brew/mdv.rb")
brew_text = <<~BREW
  class Mdv < Formula
    desc "Markdown renderer CLI in the terminal"
    homepage "https://github.com/ivan-silantev/mdv"
    version "#{version}"
    license "MIT"

    on_macos do
      if Hardware::CPU.arm?
        url "#{release_url_base}/mdv-macos-aarch64.tar.gz"
        sha256 "#{ENV.fetch("MDV_SHA_MACOS_AARCH64")}"
      else
        url "#{release_url_base}/mdv-macos-x86_64.tar.gz"
        sha256 "#{ENV.fetch("MDV_SHA_MACOS_X86_64")}"
      end
    end

    on_linux do
      if Hardware::CPU.arm?
        url "#{release_url_base}/mdv-linux-aarch64.tar.gz"
        sha256 "#{ENV.fetch("MDV_SHA_LINUX_AARCH64")}"
      else
        url "#{release_url_base}/mdv-linux-x86_64.tar.gz"
        sha256 "#{ENV.fetch("MDV_SHA_LINUX_X86_64")}"
      end
    end

    def install
      bin.install "mdv"
    end

    test do
      (testpath/"sample.md").write("# Hello\\n\\n**world**\\n")
      assert_match "Hello", shell_output("\#{bin}/mdv \#{testpath}/sample.md")
      assert_match "<h1>Hello</h1>", shell_output("\#{bin}/mdv --html \#{testpath}/sample.md")
    end
  end
BREW
File.write(brew_path, brew_text)

winget_path = File.join(repo_root, "packages/winget/IvanSilantev.mdv.yaml")
winget_text = File.read(winget_path)
winget_text.gsub!(/(?<=^PackageVersion:\s)\d+\.\d+\.\d+$/m, version)
winget_text.gsub!(/(?<=^ReleaseDate:\s)\d{4}-\d{2}-\d{2}$/m, release_date)
winget_text.gsub!(%r{https://github\.com/ivan-silantev/mdv/releases/download/v[^/]+/mdv-windows-x86_64\.zip}, "#{release_url_base}/mdv-windows-x86_64.zip")
winget_text.gsub!(/(?<=^    InstallerSha256:\s)[0-9A-F]{64}$/m, ENV.fetch("MDV_SHA_WINDOWS_X86_64").upcase)
File.write(winget_path, winget_text)

[
  File.join(repo_root, "packages/rpm/md.spec"),
  File.join(repo_root, "packages/linux/nfpm.yaml"),
  File.join(repo_root, "packages/deb/DEBIAN/control"),
].each do |path|
  text = File.read(path)
  text.gsub!(/^(\s*Version:\s*)\d+\.\d+\.\d+$/, "\\1#{version}")
  text.gsub!(/^(\s*version:\s*")\d+\.\d+\.\d+(")$/, "\\1#{version}\\2")
  File.write(path, text)
end

guide_path = File.join(repo_root, "spec/guides/publishing-brew-winget.md")
guide = File.read(guide_path)
guide.gsub!(/v\d+\.\d+\.\d+/, tag)
guide.gsub!(%r{IvanSilantev/mdv/\d+\.\d+\.\d+/}, "IvanSilantev/mdv/#{version}/")
File.write(guide_path, guide)
RUBY

echo "Artifacts:"
for artifact in \
  "$repo_root/dist/mdv-macos-aarch64.tar.gz" \
  "$repo_root/dist/mdv-macos-x86_64.tar.gz" \
  "$repo_root/dist/mdv-linux-aarch64.tar.gz" \
  "$repo_root/dist/mdv-linux-x86_64.tar.gz" \
  "$repo_root/dist/mdv-windows-x86_64.zip"
do
  printf '  %s  %s\n' "$(sha256_file "$artifact")" "${artifact#$repo_root/}"
done

if [[ "$publish" -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is required for --publish" >&2
    exit 1
  fi

  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" \
      "$repo_root/dist/mdv-macos-aarch64.tar.gz" \
      "$repo_root/dist/mdv-macos-x86_64.tar.gz" \
      "$repo_root/dist/mdv-linux-aarch64.tar.gz" \
      "$repo_root/dist/mdv-linux-x86_64.tar.gz" \
      "$repo_root/dist/mdv-windows-x86_64.zip" \
      --clobber
  else
    if [[ "$draft" -eq 1 ]]; then
      gh release create "$tag" \
        "$repo_root/dist/mdv-macos-aarch64.tar.gz" \
        "$repo_root/dist/mdv-macos-x86_64.tar.gz" \
        "$repo_root/dist/mdv-linux-aarch64.tar.gz" \
        "$repo_root/dist/mdv-linux-x86_64.tar.gz" \
        "$repo_root/dist/mdv-windows-x86_64.zip" \
        --title "$tag" \
        --notes "Release $tag" \
        --draft
    else
      gh release create "$tag" \
        "$repo_root/dist/mdv-macos-aarch64.tar.gz" \
        "$repo_root/dist/mdv-macos-x86_64.tar.gz" \
        "$repo_root/dist/mdv-linux-aarch64.tar.gz" \
        "$repo_root/dist/mdv-linux-x86_64.tar.gz" \
        "$repo_root/dist/mdv-windows-x86_64.zip" \
        --title "$tag" \
        --notes "Release $tag"
    fi
  fi
fi
