---
id: MDV-018
status: todo
priority: medium
created: 2026-05-14
updated: 2026-05-14
blocked_by: []
tags:
- tui
- pager
- terminal
- navigation
- competitive
roles:
- '@me'
---

# Explore interactive pager and TUI mode

## Task Description
- Evaluate an optional interactive reading mode for long Markdown documents.
- Focus on navigation features that improve reading without bloating the default CLI path.
- Keep non-interactive rendering fast and dependency-light.

## Context
Tools like Glow and Frogmouth compete strongly on interactive reading. `mdv` can consider a smaller pager-first mode rather than a full application-style TUI.

## Requirements
- [ ] Define scope for search, heading navigation, and table of contents shortcuts.
- [ ] Decide whether TUI mode should be built-in, optional, or a separate binary.
- [ ] Prototype pager behavior with keyboard navigation and terminal resize handling.
- [ ] Preserve plain pipe-friendly behavior for default `mdv FILE` usage.
- [ ] Document tradeoffs before selecting it for a release.

## Activity Log
- 2026-05-14: Created from competitive feature backlog discussion.
