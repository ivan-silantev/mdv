# mdv

`mdv` is a small terminal Markdown viewer written in Zig. It renders Markdown for human-friendly terminal reading and can also emit normalized HTML for tests, tooling, and automation.

## Features

- Terminal-first Markdown rendering with readable spacing and headings.
- `--html` output mode for normalized CommonMark-style HTML.
- `NO_COLOR` support for plain terminal output.
- Optional `-p` printer handoff for rendered terminal output.
- C ABI entry points for embedding the renderer from other programs.

## Install From Source

Requirements:

- Zig 0.15.x
- Git

Build and install locally:

```bash
zig build -Doptimize=ReleaseSafe
./zig-out/bin/mdv example.md
```

Install to a custom prefix:

```bash
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

## Usage

Render a Markdown file in the terminal:

```bash
mdv README.md
```

Render Markdown as HTML:

```bash
mdv --html README.md
```

Send rendered terminal output to the system printer:

```bash
mdv -p README.md
```

Show help:

```bash
mdv --help
```

## Development

Run the build and unit tests:

```bash
zig build
zig build test
```

If your environment cannot write to Zig's user-level cache, keep the cache inside the repo:

```bash
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build test
```

Run focused CommonMark fixture checks after building:

```bash
tools/commonmark_fixture_runner.py --mode html --skip-build --section "Links"
```

## Packaging

Package recipes live under `packages/`:

- `packages/brew/mdv.rb` for Homebrew taps.
- `packages/winget/IvanSilantev.mdv.yaml` for WinGet.
- `packages/linux/nfpm.yaml` for nfpm-generated Linux packages.
- `packages/deb/DEBIAN/control` and `packages/rpm/md.spec` for direct Debian/RPM metadata.

See `spec/guides/publishing-brew-winget.md` for release preparation steps.

## License

`mdv` is released under the MIT License. See `LICENSE`.
