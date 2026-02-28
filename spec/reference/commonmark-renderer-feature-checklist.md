# CommonMark renderer feature checklist

Reference spec: `spec/reference/commonmark-0.31.2.html` — CommonMark 0.31.2.

Current implementation source of truth: `src/main.zig` (`renderMarkdown`).

Legend:

- `[x]` implemented enough for the current terminal renderer
- `[~]` partially implemented, non-compliant, or only works for simple cases
- `[ ]` not implemented

## Current renderer baseline

- `[x]` Parses markdown into a lightweight block tree before rendering terminal or HTML output.
- `[x]` Supports ANSI styling for headings, quotes, bullets, code, emphasis, and strong emphasis.
- `[x]` Supports plain-text print mode via `-p` by rendering without color.
- `[~]` Uses a two-phase block/inline pipeline: phase one builds a lightweight block AST, then phase two renders each block while parsing inline content; the block model is still partial and not fully CommonMark-compliant.
- `[~]` CommonMark example fixtures can be extracted and run via `tools/commonmark_fixture_runner.py`; `--mode html` does exact normalized HTML checks against `mdv --html`, with paragraph continuation coverage improved but broader parser semantics still incomplete.

## Preliminaries

- `[~]` Characters and lines: processes file bytes line-by-line; strips trailing `\r` for CRLF lines.
- `[~]` Tabs: leading tabs are counted as 4-column stops for indented-code detection; full CommonMark tab expansion is still missing.
- `[x]` Insecure characters: terminal rendering replaces unsafe ASCII control bytes, DEL, and ESC with `�` before writing user-supplied markdown text, preventing raw ANSI/OSC escape injection while leaving tabs and renderer-owned ANSI styling intact.
- `[x]` Backslash escapes: CommonMark backslash escape fixture section passes in HTML mode, including escaped punctuation, hard-break backslashes, simple reference-link escapes, and fenced-code info strings.
- `[~]` Entity and numeric character references: common named entities (`amp`, `lt`, `gt`, `quot`, `apos`, `nbsp`) are decoded; numeric and full HTML5 entity coverage is missing.
- `[~]` Precedence: block recognition now happens before inline rendering, but the block precedence model is still incomplete.

## Leaf blocks

- `[x]` Thematic breaks: `***`, `---`, and `___` variants with spaces and up to 3 leading spaces render as terminal rules.
- `[~]` ATX headings: `#` through `######`, up to 3 leading spaces, empty headings, and closing `#` sequences are rendered; escaped-marker and full interruption rules remain incomplete.
- `[~]` Setext headings: simple underline-style `===` / `---` headings render; full paragraph/container interruption rules are incomplete.
- `[~]` Indented code blocks: HTML mode groups consecutive indented-code lines into one `<pre><code>` block and preserves internal blank lines; list/quote interaction remains incomplete.
- `[~]` Fenced code blocks: backtick and tilde fences support variable length, up to 3 leading spaces, info strings, basic info-string escaping in HTML mode, indentation stripping, and matching close markers; full container interaction is incomplete.
- `[~]` HTML blocks: simple block-level raw HTML starts are recognized and dim-rendered; full seven CommonMark HTML block types and termination rules are incomplete.
- `[~]` Link reference definitions: simple definitions are collected into the document AST and used for supported shortcut reference links; multiline definitions and full label normalization remain incomplete.
- `[~]` Paragraphs: HTML mode groups simple paragraph continuation lines and preserves hard breaks across continued lines; full interruption/lazy-continuation/container rules and terminal paragraph grouping remain incomplete.
- `[x]` Blank lines: blank input lines produce blank output lines.

## Container blocks

- `[~]` Block quotes: block parsing stores recursive child AST blocks, uses shared container-line normalization, and HTML mode renders from those children; indented marker edge cases and some fenced/indented-code interactions remain incomplete.
- `[~]` List items: block parsing stores list item metadata in the AST, including marker, normalized content, and looseness; continuation lines use shared container-line normalization, but full CommonMark indentation math and all continuation edge cases remain incomplete.
- `[~]` Ordered list items: `1. ` / `1) ` markers are recognized and rendered; HTML mode emits `start` for non-1 starts and avoids non-1 ordered-list paragraph interruption, but full CommonMark start/interruption rules are incomplete.
- `[~]` Nested lists: recursive list rendering works for some continuation-owned nested lists, but there is still no full marker/indent stack for all CommonMark nesting edge cases.
- `[~]` Tight vs loose lists: HTML mode detects blank lines inside collected list items and renders loose item content as blocks; list-wide looseness propagation is partial.
- `[~]` Lists: basic list grouping, marker-type splitting, ordered `start`, non-1 ordered paragraph interruption, AST item collection, and HTML rendering from AST items are implemented; full CommonMark list-start/list-interruption and indentation algorithms remain incomplete.

## Inline structure

- `[x]` Code spans: CommonMark code span fixture section passes in HTML mode, including multiline spans, edge-space normalization, and precedence over simple links/emphasis/autolinks.
- `[x]` Emphasis and strong emphasis: CommonMark emphasis and strong emphasis fixture section passes in HTML mode, including flanking checks, protected code/link/html spans, escaped delimiter overlap, long-run nesting, and remaining mixed-run overlap examples; terminal mode still uses simple style toggles.
- `[~]` Links: simple inline `[text](destination)` links render as underlined text; HTML mode supports empty destinations, basic titles, escaped punctuation in destinations/titles, and UTF-8 percent-encoding; reference, collapsed, shortcut, and nested labels are missing.
- `[x]` Images: CommonMark image fixture section passes in HTML mode, including inline, reference, collapsed, shortcut, and nested-label rejection cases; terminal rendering remains simplified as `[image: alt]`.
- `[x]` Autolinks: CommonMark autolink fixture section passes in HTML mode, including basic scheme/email validation and autolink-specific URL escaping.
- `[~]` Raw HTML inline: simple angle-bracket HTML-like tags are dim-rendered; full raw HTML inline grammar is incomplete.
- `[x]` Hard line breaks: CommonMark hard line break fixture section passes in HTML mode, including trailing spaces/backslashes across emphasis, code spans, and raw HTML inline text; terminal rendering remains custom-styled.
- `[x]` Soft line breaks: source line breaks are preserved as terminal line breaks.
- `[x]` Textual content: ordinary text is emitted unchanged.

## Rendering-specific features already present

- `[x]` Heading levels get distinct terminal prefixes/colors.
- `[x]` Level-1 headings get an additional decorative underline.
- `[x]` Fenced code blocks get a terminal border.
- `[x]` Block quotes get a quote bar and dim/italic styling.
- `[x]` Simple unordered list markers render as `•`; ordered list markers render as numbered prefixes.
- `[x]` Inline code gets dim/cyan styling.

## Suggested implementation order

1. Use `tools/commonmark_fixture_runner.py --mode html` to drive parser work section by section.
2. Split parsing into block phase and inline phase instead of styling one line at a time.
3. Implement block parsing first: blank lines, paragraphs, ATX/setext headings, thematic breaks, fenced/indented code, block quotes, and lists.
4. Add link reference definition collection during block parsing.
5. Implement inline parsing: escapes, entities, code spans, emphasis/strong delimiter algorithm, links, images, autolinks, raw HTML, and line breaks.
6. Keep terminal rendering separate from parsing so ANSI output can remain custom while parser behavior follows CommonMark.
7. Keep `src/main.zig` as the canonical implementation and avoid reintroducing duplicate renderers.

## Biggest gaps for CommonMark compliance

- Lightweight AST/two-phase parsing exists, but nested container nodes and inline AST precedence are still incomplete.
- No CommonMark delimiter algorithm for emphasis, links, and images.
- Lists and block quotes now have partial recursive AST support, but there is still no full CommonMark container stack/indentation algorithm.
- Fenced code, escapes, entities, references, raw HTML, autolinks, and hard breaks now have partial support but are not spec-complete.
