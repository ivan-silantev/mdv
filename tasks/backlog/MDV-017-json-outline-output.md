---
id: MDV-017
status: todo
priority: medium
created: 2026-05-14
updated: 2026-05-14
blocked_by:
- MDV-013
tags:
- cli
- json
- outline
- tooling
- competitive
roles:
- '@me'
---

# Add JSON outline and extraction output

## Task Description
- Add structured JSON output for document outlines and selected Markdown elements.
- Support tooling, indexing, and LLM/RAG workflows without requiring consumers to parse Markdown themselves.
- Keep the schema stable enough for scripts and automation.

## Context
Structured extraction can differentiate `mdv` from visual-only viewers while reusing the parser and renderer investment.

## Requirements
- [ ] Add `--json-outline` output with headings, levels, anchors, and source order.
- [ ] Add extraction options for links, images, and fenced code blocks.
- [ ] Document the JSON schema and compatibility expectations.
- [ ] Add regression tests for nested headings and duplicate anchors.
- [ ] Ensure output is valid UTF-8 JSON without ANSI styling.

## Activity Log
- 2026-05-14: Created from competitive feature backlog discussion.
