---
id: MDV-014
status: todo
priority: high
created: 2026-05-14
updated: 2026-05-14
blocked_by:
- MDV-011
- MDV-012
- MDV-013
tags:
- gfm
- commonmark
- renderer
- competitive
roles:
- '@me'
---

# Add core GitHub Flavored Markdown support

## Task Description
- Extend the renderer beyond CommonMark with high-value GitHub Flavored Markdown features.
- Prioritize README-compatible syntax that users expect from terminal Markdown viewers.
- Keep feature behavior deterministic across terminal and HTML output modes.

## Context
Competitive analysis identified GFM support as a top differentiator for `mdv`, especially for viewing project READMEs and documentation in the terminal.

## Requirements
- [ ] Support task list items with checked and unchecked states.
- [ ] Support strikethrough spans.
- [ ] Support GFM autolinks where they differ from baseline CommonMark behavior.
- [ ] Define terminal and HTML output expectations for each GFM feature.
- [ ] Add fixture coverage for both terminal and `--html` modes.

## Activity Log
- 2026-05-14: Created from competitive feature backlog discussion.
