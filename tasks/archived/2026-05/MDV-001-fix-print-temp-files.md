---
id: MDV-001
status: done
priority: high
created: 2026-05-04
updated: 2026-05-09
blocked_by: []
tags:
- bug
- portability
roles:
- '@human'
---

# Fix print temporary file handling

## Task Description
- Build print temp paths from the platform temp directory instead of hardcoding `/tmp`.
- Add cleanup immediately after creating/determining the temp path so Windows, macOS, and Unix paths all delete the file on exit.
- Avoid timestamp-only names; include enough entropy to prevent collisions between concurrent `mdv -p` runs.

## Context
See [[recommendations]] section 1.2 and 1.3.

## Activity Log
- 2026-05-04: Task identified.
- 2026-05-09: Migrated from RECOMMENDATIONS.md. Status marked as done.