---
id: MDV-015
status: todo
priority: high
created: 2026-05-14
updated: 2026-05-14
blocked_by:
- MDV-013
tags:
- gfm
- tables
- terminal
- renderer
- competitive
roles:
- '@me'
---

# Implement high-quality terminal table rendering

## Task Description
- Add Markdown table parsing and terminal rendering suitable for narrow and wide terminals.
- Handle alignment, wrapping, and readable borders without breaking copy-friendly output.
- Preserve stable HTML output for automation and test snapshots.

## Context
Table rendering is a frequent pain point in terminal Markdown viewers and can become a visible competitive advantage for `mdv`.

## Requirements
- [ ] Parse GFM table blocks with header separators and column alignment.
- [ ] Render aligned terminal tables using the current terminal width when available.
- [ ] Add fallback behavior for narrow terminals and long cell content.
- [ ] Emit stable `<table>` HTML in `--html` mode.
- [ ] Add tests for alignment, wrapping, escaped pipes, and wide Unicode content.

## Activity Log
- 2026-05-14: Created from competitive feature backlog discussion.
