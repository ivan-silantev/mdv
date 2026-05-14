---
id: MDV-016
status: todo
priority: high
created: 2026-05-14
updated: 2026-05-14
blocked_by: []
tags:
- cli
- docs-qa
- ci
- links
- competitive
roles:
- '@me'
---

# Add docs QA check mode

## Task Description
- Add a `--check` mode that validates Markdown documentation without rendering it for reading.
- Focus on CI-friendly diagnostics that help maintain project documentation quality.
- Keep checks fast, deterministic, and usable on large documentation trees.

## Context
Position `mdv` as more than a viewer: a small documentation QA tool for terminal and CI workflows.

## Requirements
- [ ] Report broken local links and missing heading anchors.
- [ ] Detect duplicate heading anchors.
- [ ] Detect malformed fenced code blocks.
- [ ] Add a machine-readable diagnostic output option for CI integration.
- [ ] Define exit codes for clean, warning, and error states.

## Activity Log
- 2026-05-14: Created from competitive feature backlog discussion.
