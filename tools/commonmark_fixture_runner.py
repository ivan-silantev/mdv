#!/usr/bin/env python3
"""Extract and run CommonMark examples against mdv.

Default mode is a terminal visible-text smoke check. Use `--mode html` to run
`mdv --html` and compare normalized HTML against the CommonMark examples.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
from html.parser import HTMLParser
from pathlib import Path

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
TOKEN_RE = re.compile(r"\S+")
DECORATION_CHARS = str.maketrans({
    "═": " ",
    "─": " ",
    "※": " ",
    "•": " ",
    "┃": " ",
    "│": " ",
    "╭": " ",
    "╰": " ",
})
BLOCK_TAGS = {
    "address", "article", "aside", "blockquote", "body", "dd", "div", "dl",
    "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2",
    "h3", "h4", "h5", "h6", "header", "hr", "html", "li", "main", "nav",
    "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot", "th",
    "thead", "tr", "ul",
}


@dataclass
class Example:
    number: int
    section: str
    markdown: str
    html: str


class CodeExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.in_code = False
        self.current_class = ""
        self.current: list[str] = []
        self.blocks: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "code":
            attrs_map = dict(attrs)
            self.current_class = attrs_map.get("class") or ""
            self.in_code = True
            self.current = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "code" and self.in_code:
            self.blocks.append((self.current_class, "".join(self.current)))
            self.in_code = False
            self.current_class = ""
            self.current = []

    def handle_data(self, data: str) -> None:
        if self.in_code:
            self.current.append(data)


class VisibleTextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "br":
            self.parts.append("\n")
        elif tag == "hr":
            self.parts.append("\n---\n")
        elif tag in BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        self.parts.append(data)

    def text(self) -> str:
        return normalize_visible_text("".join(self.parts))


def normalize_spec_text(value: str) -> str:
    return value.replace("→", "\t")


def normalize_html(value: str) -> str:
    value = value.replace("\r\n", "\n").replace("\r", "\n").strip()
    value = re.sub(r">\s+<", "><", value)
    value = re.sub(r"\s+", " ", value)
    value = value.replace("> <", "><")
    return value.strip()


def normalize_visible_text(value: str) -> str:
    lines = [line.strip() for line in value.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    compact: list[str] = []
    previous_blank = False
    for line in lines:
        blank = line == ""
        if blank and previous_blank:
            continue
        compact.append(line)
        previous_blank = blank
    return "\n".join(compact).strip()


def strip_terminal_output(value: str) -> str:
    stripped = ANSI_RE.sub("", value).translate(DECORATION_CHARS)
    stripped = re.sub(r"\bCode(?:\s+\([^)]*\))?\b", " ", stripped)
    return normalize_visible_text(stripped)


def visible_text_from_html(value: str) -> str:
    parser = VisibleTextExtractor()
    parser.feed(value)
    return parser.text()


def tokens(value: str) -> list[str]:
    return TOKEN_RE.findall(value)


def is_subsequence(needles: list[str], haystack: list[str]) -> bool:
    pos = 0
    for needle in needles:
        while pos < len(haystack) and haystack[pos] != needle:
            pos += 1
        if pos == len(haystack):
            return False
        pos += 1
    return True


def extract_examples(spec_path: Path) -> list[Example]:
    source = spec_path.read_text(encoding="utf-8")
    heading_matches = list(re.finditer(r'<h[1-3] id="[^"]+" class="definition">(.*?)</h[1-3]>', source, re.S))
    example_re = re.compile(r'<div class="example" id="example-(\d+)">(.*?)</div>\s*</div>', re.S)
    examples: list[Example] = []

    for match in example_re.finditer(source):
        number = int(match.group(1))
        body = match.group(2)
        section = "Unknown"
        for heading in heading_matches:
            if heading.start() < match.start():
                section = re.sub(r"^\s*[0-9.]+\s*", "", re.sub(r"<.*?>", "", heading.group(1)).strip())
            else:
                break

        extractor = CodeExtractor()
        extractor.feed(body)
        markdown = None
        expected_html = None
        for class_name, code in extractor.blocks:
            if "language-markdown" in class_name and markdown is None:
                markdown = normalize_spec_text(code)
            elif "language-html" in class_name and expected_html is None:
                expected_html = normalize_spec_text(code)
        if markdown is None or expected_html is None:
            continue
        examples.append(Example(number=number, section=section, markdown=markdown, html=expected_html))

    return examples


def build_binary(repo: Path, skip_build: bool) -> Path:
    binary = repo / "zig-out" / "bin" / "mdv"
    if not skip_build:
        subprocess.run(["zig", "build"], cwd=repo, check=True)
    if not binary.exists():
        raise SystemExit(f"Binary not found: {binary}. Run `zig build` first.")
    return binary


def run_example(binary: Path, markdown: str, html_mode: bool = False) -> tuple[int, str, str]:
    with tempfile.NamedTemporaryFile("w", suffix=".md", encoding="utf-8", delete=False) as tmp:
        tmp.write(markdown)
        tmp_path = Path(tmp.name)
    try:
        cmd = [str(binary)]
        if html_mode:
            cmd.append("--html")
        cmd.append(str(tmp_path))
        proc = subprocess.run(cmd, text=True, capture_output=True)
        return proc.returncode, proc.stdout, proc.stderr
    finally:
        tmp_path.unlink(missing_ok=True)


def run_fixtures(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    examples = extract_examples(Path(args.spec))
    if args.section:
        examples = [example for example in examples if args.section.lower() in example.section.lower()]
    if args.examples:
        wanted = {int(item) for part in args.examples for item in part.split(",") if item.strip()}
        examples = [example for example in examples if example.number in wanted]
    if args.limit is not None:
        examples = examples[: args.limit]

    binary = build_binary(repo, args.skip_build)
    passed = 0
    failed: list[tuple[Example, str, str]] = []
    by_section: dict[str, list[int]] = {}

    for example in examples:
        code, stdout, stderr = run_example(binary, example.markdown, args.mode == "html")
        if args.mode == "html":
            actual_text = normalize_html(stdout)
            expected_text = normalize_html(example.html)
            ok = code == 0 and actual_text == expected_text
        else:
            actual_text = strip_terminal_output(stdout)
            expected_text = visible_text_from_html(example.html)
            expected_tokens = tokens(expected_text)
            actual_tokens = tokens(actual_text)
            ok = code == 0 and (not expected_tokens or is_subsequence(expected_tokens, actual_tokens) or expected_text in actual_text)
        by_section.setdefault(example.section, [0, 0])[1] += 1
        if ok:
            passed += 1
            by_section[example.section][0] += 1
        else:
            failed.append((example, expected_text, actual_text or stderr.strip()))

    total = len(examples)
    label = "HTML exact" if args.mode == "html" else "terminal smoke"
    print(f"CommonMark {label}: {passed}/{total} checks passed")
    print("\nBy section:")
    for section, (section_passed, section_total) in sorted(by_section.items()):
        print(f"  {section}: {section_passed}/{section_total}")

    if failed:
        print("\nFirst failures:")
        for example, expected_text, actual_text in failed[: args.show_failures]:
            print(f"\nExample {example.number} — {example.section}")
            print("Markdown:")
            print(example.markdown.rstrip())
            print("Expected visible text:")
            print(expected_text or "<no visible text>")
            print("Actual terminal text:")
            print(actual_text or "<empty>")

    return 0 if not failed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="CommonMark fixture extractor/smoke runner for mdv")
    parser.add_argument("--spec", default="spec/reference/commonmark-0.31.2.html", help="Path to downloaded CommonMark spec HTML")
    parser.add_argument("--repo", default=".", help="Repository root")
    parser.add_argument("--extract-out", help="Write extracted examples JSON and exit")
    parser.add_argument("--section", help="Run only examples whose section contains this text")
    parser.add_argument("--examples", nargs="*", help="Run specific example numbers, comma-separated or space-separated")
    parser.add_argument("--limit", type=int, help="Run only the first N selected examples")
    parser.add_argument("--show-failures", type=int, default=10, help="How many failing examples to print")
    parser.add_argument("--mode", choices=("terminal", "html"), default="terminal", help="terminal visible-text smoke or exact normalized HTML comparison")
    parser.add_argument("--skip-build", action="store_true", help="Use existing zig-out/bin/mdv")
    args = parser.parse_args()

    if args.extract_out:
        examples = extract_examples(Path(args.spec))
        Path(args.extract_out).write_text(json.dumps([asdict(example) for example in examples], ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Wrote {len(examples)} examples to {args.extract_out}")
        return 0

    return run_fixtures(args)


if __name__ == "__main__":
    sys.exit(main())
