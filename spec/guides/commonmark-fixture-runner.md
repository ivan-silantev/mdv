# CommonMark fixture runner

`tools/commonmark_fixture_runner.py` extracts examples from `spec/reference/commonmark-0.31.2.html` and runs them against the current Zig renderer.

It supports two modes:

- `terminal`: visible-text smoke checks for the default ANSI terminal renderer.
- `html`: exact normalized HTML checks using `mdv --html`.

## Commands

Build and run the first 50 examples in terminal smoke mode:

```sh
tools/commonmark_fixture_runner.py --limit 50
```

Run exact HTML checks with an already-built `zig-out/bin/mdv` binary:

```sh
tools/commonmark_fixture_runner.py --skip-build --mode html --limit 50
```

Run one section:

```sh
tools/commonmark_fixture_runner.py --mode html --section "ATX headings"
```

Run specific examples:

```sh
tools/commonmark_fixture_runner.py --examples 1,2,3 14
```

Extract all spec examples to JSON:

```sh
tools/commonmark_fixture_runner.py --extract-out /tmp/commonmark-examples.json
```

## Current use

Use `--mode html` as the main compliance signal and `--mode terminal` as a regression signal for the styled terminal output. The most useful number is the section summary, because it quickly shows which CommonMark areas regress after parser changes.
