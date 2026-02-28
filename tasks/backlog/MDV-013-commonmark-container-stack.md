---
id: MDV-013
status: todo
priority: medium
created: 2026-05-11
updated: 2026-05-11
blocked_by: []
tags:
- commonmark
- parser
- lists
- blockquotes
roles:
- '@me'
---

# Replace partial container parsing with CommonMark indentation stack

## Task Description
- Track nested block quote and list containers with CommonMark-compatible indentation math.
- Remove ad-hoc continuation handling that reparses nested list and quote content.
- Make loose/tight list propagation follow the full parsed container tree.

## Context
See [[commonmark-renderer-feature-checklist]] sections "Container blocks" and "Biggest gaps for CommonMark compliance".

## Requirements
- [ ] Define parser state for open containers and paragraph continuation.
- [ ] Add focused nested list and block quote fixtures before refactoring.
- [ ] Verify `List items`, `Block quotes`, and related fixture sections.

## Activity Log
- 2026-05-11: Created from CommonMark renderer checklist gap.
