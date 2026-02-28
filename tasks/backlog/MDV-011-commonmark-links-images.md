---
id: MDV-011
status: todo
priority: high
created: 2026-05-11
updated: 2026-05-11
blocked_by: []
tags:
- commonmark
- links
- images
- renderer
roles:
- '@me'
---

# Finish CommonMark link edge cases

## Task Description
- Close remaining `Links` fixture failures in HTML mode.
- Reject invalid bracketed destinations containing source newlines or escaped closing delimiters as required by CommonMark.
- Keep image parsing at full CommonMark fixture coverage while links are completed.

## Context
See [[commonmark-renderer-feature-checklist]] section "Inline structure".

## Requirements
- [ ] Add targeted fixtures for invalid bracketed destinations.
- [x] Add targeted fixtures for nested image labels like `![[foo]]`.
- [ ] Verify the `Links` and `Images` fixture sections.

## Activity Log
- 2026-05-11: Created from CommonMark renderer checklist gap and fixture failures.
- 2026-05-11: Fixed nested-label image/reference handling; `Images` now passes 22/22 in HTML mode. `Links` improved to 61/90 and remains open.
- 2026-05-11: Improved inline link target/title parsing, escaped reference labels, adjacent reference definitions, nested-link suppression, and URL entity encoding. `Links` now passes 82/90; `Images` remains 22/22. Remaining failures are CommonMark examples 491, 493, 494, 520, 534, 541, 564, and 568.
