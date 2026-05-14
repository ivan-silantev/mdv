# Publishing mdv to Homebrew and WinGet

This project installs the `mdv` binary from `build.zig`; package metadata should use `mdv`, not `md`.

## 1. Create a release tag

Before submitting to package repositories, make sure the release repository contains a `LICENSE` file matching the `MIT` metadata in the package manifests.

```sh
git tag v0.1.0
git push origin v0.1.0
```

## 2. Build the release archives

```sh
mkdir -p dist

zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe --prefix dist/mdv-macos-aarch64
cp dist/mdv-macos-aarch64/bin/mdv dist/mdv
tar -C dist -czf dist/mdv-macos-aarch64.tar.gz mdv

zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe --prefix dist/mdv-macos-x86_64
cp dist/mdv-macos-x86_64/bin/mdv dist/mdv
tar -C dist -czf dist/mdv-macos-x86_64.tar.gz mdv

zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe --prefix dist/mdv-linux-aarch64
cp dist/mdv-linux-aarch64/bin/mdv dist/mdv
tar -C dist -czf dist/mdv-linux-aarch64.tar.gz mdv

zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe --prefix dist/mdv-linux-x86_64
cp dist/mdv-linux-x86_64/bin/mdv dist/mdv
tar -C dist -czf dist/mdv-linux-x86_64.tar.gz mdv

zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe
mkdir -p dist/mdv-windows-x86_64
cp zig-out/bin/mdv.exe dist/mdv-windows-x86_64/mdv.exe
(cd dist/mdv-windows-x86_64 && zip -9 -X ../mdv-windows-x86_64.zip mdv.exe)

shasum -a 256 \
  dist/mdv-macos-aarch64.tar.gz \
  dist/mdv-macos-x86_64.tar.gz \
  dist/mdv-linux-aarch64.tar.gz \
  dist/mdv-linux-x86_64.tar.gz \
  dist/mdv-windows-x86_64.zip
```

Upload all five archives to the GitHub release `v0.1.0`. If you rebuild any archive, update the matching checksum in:

- `packages/brew/mdv.rb` for the macOS/Linux tarballs
- `packages/winget/IvanSilantev.mdv.yaml` for the Windows ZIP

## 3. Confirm the Homebrew release URLs

The Homebrew formula downloads a prebuilt binary archive from the GitHub release:

```sh
brew install ./packages/brew/mdv.rb
```

## 4. Validate locally

```sh
brew audit --strict --online packages/brew/mdv.rb
brew install ./packages/brew/mdv.rb
winget validate packages/winget/IvanSilantev.mdv.yaml
```

The WinGet manifest uses `InstallerType: zip` with `NestedInstallerType: portable` because the release asset is a ZIP archive containing `mdv.exe`.

## 5. Submit

- Homebrew: copy `packages/brew/mdv.rb` into your tap, for example `homebrew-tap/Formula/mdv.rb`, and open a PR.
- WinGet: submit `packages/winget/IvanSilantev.mdv.yaml` to `microsoft/winget-pkgs` under `manifests/i/IvanSilantev/mdv/0.1.0/`.
