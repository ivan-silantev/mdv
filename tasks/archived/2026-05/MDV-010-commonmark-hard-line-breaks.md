---
id: MDV-010
status: done
priority: high
created: 2026-05-11
updated: 2026-05-11
blocked_by: []
tags:
- commonmark
- html
- renderer
roles:
- '@me'
---

# Complete CommonMark hard line breaks in HTML mode

## Task Description
- Preserve hard line breaks inside multi-line paragraph blocks.
- Support both trailing backslash and two-or-more trailing spaces before a source newline.
- Keep soft line breaks distinct from hard breaks in generated HTML.

## Context
See [[commonmark-renderer-feature-checklist]] section "Inline structure" and CommonMark examples 633-639.

## Requirements
- [x] Fix HTML paragraph rendering for continued lines ending in hard-break syntax.
- [x] Add focused regression coverage for trailing-space and trailing-backslash hard breaks.
- [x] Verify the `Hard line breaks` fixture section.

## Activity Log
- 2026-05-11: Created from CommonMark renderer checklist gap.
- 2026-05-11: Implemented inline hard-break handling and verified `Hard line breaks` at 15/15 in HTML mode.
