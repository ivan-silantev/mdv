---
id: MDV-012
status: todo
priority: medium
created: 2026-05-11
updated: 2026-05-11
blocked_by: []
tags:
- commonmark
- html
- parser
roles:
- '@me'
---

# Complete CommonMark HTML block parsing rules

## Task Description
- Implement all seven CommonMark HTML block start and termination types.
- Preserve raw HTML block boundaries without swallowing following paragraph content.
- Handle HTML block parsing inside block quotes and other containers.

## Context
See [[commonmark-renderer-feature-checklist]] sections "Leaf blocks" and "Biggest gaps for CommonMark compliance".

## Requirements
- [ ] Add regression coverage for current HTML block fixture failures.
- [ ] Implement remaining HTML block termination rules.
- [ ] Verify the `HTML blocks` fixture section.

## Activity Log
- 2026-05-11: Created from CommonMark renderer checklist gap.
