---
id: MDV-006
status: done
priority: medium
created: 2026-05-04
updated: 2026-05-09
blocked_by: []
tags:
- feature
- terminal
roles:
- '@human'
---

# Honor NO_COLOR for terminal output

## Task Description
- Detect a non-empty `NO_COLOR` environment variable before rendering terminal output.
- Disable ANSI styles for normal rendering, usage text, and error messages when `NO_COLOR` is set.
- Keep HTML output unaffected.

## Context
See [[recommendations]] section 3.3.

## Activity Log
- 2026-05-04: Task identified.
- 2026-05-09: Migrated from RECOMMENDATIONS.md. Status marked as done.