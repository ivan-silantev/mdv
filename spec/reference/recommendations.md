# Codebase Review & Recommendations: `mdv` (Markdown Viewer)

This document outlines identified issues, memory leaks, code smells, and general recommendations for the `mdv` project.

## Validation Summary

Reviewed against `src/main.zig` on 2026-05-04.

### Worth implementing now

- **1.3 Temporary File Leaks** — valid bug. `printRenderedDocument` returns early on Windows and macOS before the cleanup `defer`, so generated print files are left behind.
- **1.4 URL Percent-Encoding Bug** — valid bug. `writeHtmlUrlAttribute` percent-encodes the first space/tab, then skips following spaces/tabs, which changes URLs with consecutive whitespace.
- **1.2 Non-Portable Temporary Paths** — valid portability issue. `printRenderedDocument` always writes under `/tmp`, which is not portable to Windows and ignores platform temp-directory conventions.

### Valid, but lower priority or needs care

- **2.1 Overuse of `page_allocator`** — valid performance/architecture concern. The current implementation has been updated to thread an explicit allocator through the parser/render path instead of hardcoding `std.heap.page_allocator`; future work can still consider arena allocation per render pass.
- **2.2 Inefficient IO Operations** — valid micro-optimization. It should be done opportunistically after correctness work, not as a standalone urgent task.
- **2.3 Redundant Parsing (Double Work)** — partially stale. HTML rendering already uses `renderHtmlAstBlock` for many block types, but terminal rendering and fallback paths still re-render from `block.source`. Continue the AST migration rather than deleting all legacy block renderers immediately.
- **3.1 Monolithic Source File** — valid maintainability issue, but risky as a broad refactor while CommonMark behavior is still changing. Do only after adding regression coverage.
- **3.2 Silent Overflow in `ContainerStack`** — valid correctness issue for deeply nested containers. Prefer returning an explicit parser error or moving to dynamic storage.
- **3.3 Hardcoded ANSI Sequences** — partially addressed. Existing color gating now honors `NO_COLOR`; a richer theme/style abstraction can remain a later enhancement.
- **4.1 Lack of Unit Tests** — valid. The project has fixture tooling, but focused Zig tests for parser and escaping helpers would make small bug fixes safer.
- **4.2 Error Handling** — valid but broad. Apply incrementally when touching parser/container code.

### Not recommended as written

- **3.4 Non-Idiomatic IO Wrappers** — likely not valid for the current Zig version used by this project (`zig 0.15.2`). The `.writer(&.{})` / `.interface` pattern is consistent with Zig's newer IO API here, so this should not be changed unless the project intentionally targets a different Zig version.
- **1.1 HTML Escaping Inconsistency** — rejected after implementation/testing. Escaping `>` as `&gt;` in text nodes regressed CommonMark exact HTML output for code span fixtures; keep literal `>` in text nodes while escaping it in attributes.

## Implementation Tasks

### Task 1: Fix print temporary file handling

Status: **implemented** in `src/main.zig`.

- Build print temp paths from the platform temp directory instead of hardcoding `/tmp`.
- Add cleanup immediately after creating/determining the temp path so Windows, macOS, and Unix paths all delete the file on exit.
- Avoid timestamp-only names; include enough entropy to prevent collisions between concurrent `mdv -p` runs.
- Validate by running `zig build` and a small `mdv -p` smoke test where possible.

### Task 2: Fix HTML URL whitespace encoding

Status: **implemented** in `src/main.zig`.

- Update `writeHtmlUrlAttribute` so every space and tab is percent-encoded individually.
- Add focused coverage for destinations containing consecutive spaces/tabs, including escaped punctuation behavior.
- Validate with `tools/commonmark_fixture_runner.py --skip-build --mode html --section "Links" --show-failures 5` after building.

### Task 3: Normalize text-node HTML escaping

Status: **rejected after validation**. `writeHtmlEscaped` intentionally keeps literal `>` in text nodes because `tools/commonmark_fixture_runner.py --mode html --section "Code spans"` regressed when `>` was changed to `&gt;`.

- Change `writeHtmlEscaped` to emit `&gt;` for `>`.
- Add or update a focused HTML escaping test/smoke case for `&`, `<`, `>`, and quotes in text vs attributes.
- Re-run relevant HTML fixture sections to ensure no intentional raw-HTML behavior regresses.

### Task 4: Add focused regression tests before refactors

Status: **partially implemented** in `src/main.zig`; escaping, URL attributes, temp-path construction, and `ContainerStack` overflow are covered. Broader nested block quote/list fixture coverage is still needed before large parser refactors.

- Add Zig `test` blocks or a small fixture-based smoke script for escaping, URL attributes, temp-path construction, and container nesting boundaries.
- Keep tests near the functions they cover until the project is split into modules.
- Use these tests as the safety net before allocator, AST-rendering, or module-splitting refactors.

### Task 5: Plan parser/render architecture cleanup

Status: **partially implemented**. Markdown/HTML render paths now accept an explicit allocator instead of hardcoding `std.heap.page_allocator`, and `ContainerStack.push` now reports overflow. Full AST-renderer migration and module splitting remain intentionally deferred until more parser regression coverage exists.

- Thread an explicit allocator through `renderMarkdown`, `renderHtmlMarkdown`, and helper renderers instead of hardcoding `std.heap.page_allocator`.
- Continue migrating terminal and HTML output to consume `AstBlock` directly, leaving legacy source-based renderers only as temporary fallbacks.
- Replace silent `ContainerStack.push` overflow with an explicit error or dynamic stack after parser tests exist.
- Defer large file-splitting until the above behavior is covered by regression tests.

### Task 6: Honor NO_COLOR for terminal output

Status: **implemented** in `src/main.zig`.

- Detect a non-empty `NO_COLOR` environment variable before rendering terminal output.
- Disable ANSI styles for normal rendering, usage text, and error messages when `NO_COLOR` is set.
- Keep HTML output unaffected.

## 1. Critical Issues & Bugs

### 1.1 HTML Escaping Inconsistency
- **Issue:** In `writeHtmlEscaped`, the `>` character is printed literally instead of being escaped as `&gt;`.
- **Impact:** Potential for broken HTML output if the markdown content contains certain character combinations, although `<` and `&` are handled.
- **Recommendation:** Update `writeHtmlEscaped` to consistently escape `>` as `&gt;`, similar to `writeHtmlAttribute`.

### 1.2 Non-Portable Temporary Paths
- **Issue:** `printRenderedDocument` hardcodes `/tmp/mdv-print-{d}.txt`.
- **Impact:** This will fail on Windows systems where `/tmp/` does not exist as an absolute path.
- **Recommendation:** Use `std.fs.getAppDataDir` or check the `TMPDIR` / `TEMP` environment variables to determine a valid temporary directory for the current OS.

### 1.3 Temporary File Leaks
- **Issue:** In `printRenderedDocument`, the temporary file is only deleted on non-Windows/non-macOS systems. The functions for Windows and macOS return early before reaching the `defer std.fs.deleteFileAbsolute` call.
- **Impact:** Disk space accumulation in the temporary directory over time.
- **Recommendation:** Move the `defer` cleanup to the top of the function, immediately after the temporary file path is determined, and ensure it covers all exit paths.

### 1.4 URL Percent-Encoding Bug
- **Issue:** `writeHtmlUrlAttribute` contains a loop that skips multiple spaces or tabs after the first one is percent-encoded.
- **Impact:** URLs with multiple consecutive spaces will be incorrectly encoded (only the first space is preserved).
- **Recommendation:** Remove the `while` loop that skips characters; every character that needs encoding should be encoded individually.

---

## 2. Memory Management & Performance

### 2.1 Overuse of `page_allocator`
- **Issue:** The code frequently uses `std.heap.page_allocator` for small, transient allocations (e.g., AST construction, paragraph buffering, block parsing).
- **Impact:** High performance overhead due to frequent system calls (`mmap`/`munmap`). Each allocation likely requests a full page from the OS.
- **Recommendation:** 
    - Use a `std.heap.ArenaAllocator` for the duration of a parsing/rendering pass.
    - Pass an `allocator` explicitly to all functions that require it instead of relying on global or hardcoded allocators.
    - Use the `gpa` initialized in `main` for long-lived allocations.

### 2.2 Inefficient IO Operations
- **Issue:** Many functions use `writer.print("{c}", .{char})` or `writer.print("{s}", .{string})` for single characters or static strings.
- **Impact:** `print` involves format string parsing which is unnecessary for single bytes or known strings.
- **Recommendation:** Use `writer.writeByte(char)` and `writer.writeAll(string)` for improved performance.

### 2.3 Redundant Parsing (Double Work)
- **Issue:** `renderMarkdown` and `renderHtmlMarkdown` both construct a full AST via `parseCommonMarkBlocks`, but then call `renderMarkdownBlocks` or `renderHtmlMarkdownBlocks` on the *source* of each block. These "Blocks" functions effectively re-parse the content to identify headings, lists, etc.
- **Impact:** Significant CPU waste re-identifying block types that were already determined during AST construction.
- **Recommendation:** Refactor the rendering logic to consume the `AstBlock` structures directly. The `renderHtmlAstBlock` function is a good start, but it should be used exclusively, and the "Blocks" re-parsing functions should be eliminated.

---

## 3. Code Smells & Architecture

### 3.1 Monolithic Source File
- **Issue:** `src/main.zig` is over 2,300 lines long, containing everything from argument parsing and OS-specific terminal logic to the full CommonMark parser and multiple renderers.
- **Impact:** Difficult maintenance, poor discoverability, and long compilation times.
- **Recommendation:** Split the file into modules:
    - `args.zig`: CLI option parsing.
    - `terminal.zig`: OS-specific terminal size and styling logic.
    - `ast.zig`: Data structures for the Markdown AST.
    - `parser.zig`: The logic for turning text into an AST.
    - `render_terminal.zig`: The terminal-based renderer.
    - `render_html.zig`: The HTML renderer.

### 3.2 Silent Overflow in `ContainerStack`
- **Issue:** `ContainerStack.push` silently returns if the stack (fixed size 16) is full.
- **Impact:** Deeply nested lists or block quotes will be parsed incorrectly without any indication of error.
- **Recommendation:** Return an error (e.g., `error.StackOverflow`) when the limit is reached, or use a `std.ArrayList` for dynamic nesting depth.

### 3.3 Hardcoded ANSI Sequences
- **Issue:** ANSI escape codes like `\x1b[31m` are hardcoded as string constants.
- **Impact:** Brittle and difficult to theme or disable (currently handled by an `enabled` check in a helper function, which is better than nothing).
- **Recommendation:** Use a more robust styling abstraction that can easily support "no-color" modes (following the `NO_COLOR` standard) or different themes.

### 3.4 Non-Idiomatic IO Wrappers
- **Issue:** Use of `&writer.interface` and `writer(&.{})` suggests a non-standard or legacy way of interacting with Zig's IO system.
- **Impact:** Confusion for developers familiar with standard Zig `std.io.Writer` patterns.
- **Recommendation:** Align with standard Zig idioms: `std.io.getStdOut().writer()` and passing writers by `anytype` without requiring an `.interface` field unless explicitly using a dynamic dispatch pattern.

---

## 4. Engineering Standards

### 4.1 Lack of Unit Tests
- **Issue:** While there are some standalone test files in the root, the main parser and rendering logic lack comprehensive unit tests within `src/main.zig` or associated modules.
- **Recommendation:** Add Zig `test` blocks to verify individual parsing functions (e.g., `parseAtxHeading`, `parseLinkTarget`) and ensure correctness across various edge cases.

### 4.2 Error Handling
- **Issue:** Some errors are swallowed or converted to generic `anyerror`.
- **Recommendation:** Use specific error sets to improve debuggability and allow the caller to handle different failure modes appropriately.
