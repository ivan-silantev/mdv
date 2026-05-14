# Publishing mdv to Homebrew and WinGet

This project installs the `mdv` binary from `build.zig`; package metadata should use `mdv`, not `md`.

## 1. Create a release tag

Before submitting to package repositories, make sure the release repository contains a `LICENSE` file matching the `MIT` metadata in the package manifests.

```sh
git tag v0.1.0
git push origin v0.1.0
```

## 2. Build the Windows portable archive

```sh
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe
mkdir -p dist/mdv-windows-x86_64
cp zig-out/bin/mdv.exe dist/mdv-windows-x86_64/mdv.exe
(cd dist/mdv-windows-x86_64 && zip -9 -X ../mdv-windows-x86_64.zip mdv.exe)
shasum -a 256 dist/mdv-windows-x86_64.zip
```

Upload `dist/mdv-windows-x86_64.zip` to the GitHub release `v0.1.0`. If you rebuild the ZIP, update `InstallerSha256` in `packages/winget/IvanSilantev.mdv.yaml` with the new checksum.

## 3. Confirm the Homebrew tag URL

The Homebrew formula builds from the Git tag directly:

```sh
brew install --build-from-source ./packages/brew/mdv.rb
```

## 4. Validate locally

```sh
brew audit --strict --online packages/brew/mdv.rb
brew install --build-from-source ./packages/brew/mdv.rb
winget validate packages/winget/IvanSilantev.mdv.yaml
```

The WinGet manifest uses `InstallerType: zip` with `NestedInstallerType: portable` because the release asset is a ZIP archive containing `mdv.exe`.

## 5. Submit

- Homebrew: copy `packages/brew/mdv.rb` into your tap, for example `homebrew-tap/Formula/mdv.rb`, and open a PR.
- WinGet: submit `packages/winget/IvanSilantev.mdv.yaml` to `microsoft/winget-pkgs` under `manifests/i/IvanSilantev/mdv/0.1.0/`.
