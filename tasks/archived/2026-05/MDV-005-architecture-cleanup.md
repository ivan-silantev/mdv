---
id: MDV-005
status: done
priority: medium
created: 2026-05-04
updated: 2026-05-09
blocked_by: []
tags:
- refactor
- architecture
roles:
- '@human'
---

# Plan parser/render architecture cleanup

## Task Description
- Thread an explicit allocator through `renderMarkdown`, `renderHtmlMarkdown`, and helper renderers instead of hardcoding `std.heap.page_allocator`.
- Continue migrating terminal and HTML output to consume `AstBlock` directly, leaving legacy source-based renderers only as temporary fallbacks.
- Replace silent `ContainerStack.push` overflow with an explicit error or dynamic stack after parser tests exist.
- Defer large file-splitting until the above behavior is covered by regression tests.

## Context
See [[recommendations]] sections 2.1, 2.3, 3.1, 3.2.

## Activity Log
- 2026-05-04: Task identified.
- 2026-05-09: Migrated from RECOMMENDATIONS.md. Currently partially implemented (allocator threading and ContainerStack overflow reporting).
- 2026-05-09: Migrated `.thematic_break`, `.html_block`, `.blank`, `.indented_code`, and `.fenced_code` block rendering in the terminal to consume `AstBlock` directly, reducing reliance on legacy `renderMarkdownBlocks`.