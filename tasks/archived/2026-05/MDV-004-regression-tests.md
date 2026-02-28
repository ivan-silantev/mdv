---
id: MDV-004
status: done
priority: high
created: 2026-05-04
updated: 2026-05-09
blocked_by: []
tags:
- testing
- regression
roles:
- '@human'
---

# Add focused regression tests before refactors

## Task Description
- Add Zig `test` blocks or a small fixture-based smoke script for escaping, URL attributes, temp-path construction, and container nesting boundaries.
- Keep tests near the functions they cover until the project is split into modules.
- Use these tests as the safety net before allocator, AST-rendering, or module-splitting refactors.

## Context
See [[recommendations]] section 4.1.

## Activity Log
- 2026-05-04: Task identified.
- 2026-05-09: Migrated from RECOMMENDATIONS.md. Currently partially implemented (escaping, URL attributes, temp-path construction, and ContainerStack overflow are covered).
- 2026-05-09: Completed by adding `test` step to `build.zig`, fixing the `tools/commonmark_fixture_runner.py` smoke script default path, and adding a `ContainerStack evaluates nesting boundaries` test to `src/renderer.zig`.