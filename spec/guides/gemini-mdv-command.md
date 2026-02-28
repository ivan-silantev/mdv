# Gemini CLI `/mdv` command

This repository includes a project-local Gemini CLI custom command at `.gemini/commands/mdv.toml`.

Use it from an interactive Gemini CLI session opened at the repository root:

```text
/mdv example.md
```

Gemini CLI will ask for approval to run the shell command, then inject the output of:

```sh
./zig-out/bin/mdv example.md
```

After changing command files, reload them without restarting Gemini CLI:

```text
/commands reload
```

If `./zig-out/bin/mdv` does not exist yet, build it first:

```sh
zig build
```
