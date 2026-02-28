---
id: MDV-003
status: done
priority: medium
created: 2026-05-04
updated: 2026-05-09
blocked_by: []
tags:
- research
- rejected
roles:
- '@human'
---

# Normalize text-node HTML escaping

## Task Description
- Change `writeHtmlEscaped` to emit `&gt;` for `>`.
- Add or update a focused HTML escaping test/smoke case for `&`, `<`, `>`, and quotes in text vs attributes.

## Context
See [[recommendations]] section 1.1 and 3.3.

## Activity Log
- 2026-05-04: Task identified.
- 2026-05-09: Migrated from RECOMMENDATIONS.md.
- 2026-05-09: Rejected after validation. `writeHtmlEscaped` intentionally keeps literal `>` in text nodes to avoid regressing CommonMark code span fixtures.