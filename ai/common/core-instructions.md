# AI Instructions for Spectre

When working within this repository, adhere to the following rules to ensure consistency and token efficiency:

1. **Source of Truth:** Always refer to `README.md` for the system specification.
2. **File-Based State:** Do not assume any external database. Read `.md` files in `tasks/` and `spec/` to understand current state.
3. **Task Updates:**
   - Update YAML frontmatter meticulously (ensure `updated` date is current).
   - Use surgical edits (e.g., `replace`) rather than overwriting files to save tokens and maintain history.
   - Keep `Activity Log` entries concise.
4. **MCP Integration:**
   - Always use `mcp_spectre_*` tools (e.g., `mcp_spectre_change_task`, `mcp_spectre_move_task`) for task mutations (status, priority, location).
   - Refer to `mcp-config.json` in the root for server configuration if needed.
5. **Git Integration:** Mention that changes should be committed with descriptive messages.
5. **Coding (Rust):**
   - Follow idiomatic Rust patterns.
   - Use `ratatui` for TUI components.
   - Prioritize performance and minimal dependencies.
6. **Token Efficiency:** 
   - Be concise in your responses.
   - Use bullet points.
   - Don't repeat existing documentation; reference it by path.
