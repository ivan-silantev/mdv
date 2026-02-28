---
id: MDV-002
status: done
priority: high
created: 2026-05-04
updated: 2026-05-09
blocked_by: []
tags:
- bug
- encoding
roles:
- '@human'
---

# Fix HTML URL whitespace encoding

## Task Description
- Update `writeHtmlUrlAttribute` so every space and tab is percent-encoded individually.
- Add focused coverage for destinations containing consecutive spaces/tabs, including escaped punctuation behavior.

## Context
See [[recommendations]] section 1.4.

## Activity Log
- 2026-05-04: Task identified.
- 2026-05-09: Migrated from RECOMMENDATIONS.md. Status marked as done.