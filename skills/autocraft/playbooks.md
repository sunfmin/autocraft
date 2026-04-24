# Playbook Management

*Reference for creating, updating, and managing playbooks. Playbooks live inside this skill at `skills/autocraft/playbooks/` — no network, no gist. Loaded by the Orchestrator at invocation time (see [orchestrator.md](orchestrator.md) Step 2).*

## Layout

```
skills/autocraft/playbooks/
  registry.json             # platform → file map
  playbook-macos.md         # one file per platform (any kebab-case name)
  playbook-web.md
  ...
```

Each platform playbook is a single markdown file containing multiple `# {Heading}` sections. The Orchestrator splits on H1s and routes each section to the relevant agent (see [orchestrator.md](orchestrator.md) for the routing rules).

## Registry format

`playbooks/registry.json`:

```json
{
  "playbooks": [
    {
      "platform": "macos",
      "path": "playbook-macos.md",
      "description": "Xcode, SwiftUI, XCUITest, codesign, ScreenCaptureKit"
    }
  ]
}
```

- `platform` — lowercase, no spaces (`macos`, `web`, `ios`, `android`, `go`, `python`, …)
- `path` — filename relative to `playbooks/` (not a gist ID)
- `description` — one-line human summary

## Project-level override

A project can point autocraft at a different playbook set by writing `autocraft/config.json` alongside `spec.md`:

```json
{
  "playbooks_path": "tools/my-playbooks/"
}
```

Resolution order:
1. `autocraft/config.json` → `playbooks_path` relative to the spec file's parent directory
2. Fallback → the skill's own `skills/autocraft/playbooks/`

## Adding a new playbook

1. Write a new file at `skills/autocraft/playbooks/playbook-{platform}.md` with H1 sections (see format below).
2. Add an entry to `playbooks/registry.json`:
   ```json
   {
     "platform": "web",
     "path": "playbook-web.md",
     "description": "Playwright, Vite, CORS"
   }
   ```
3. `git commit` in the autocraft repo. Next invocation loads it; every user inherits it on pull.

## Updating an existing entry

1. Edit `skills/autocraft/playbooks/playbook-<platform>.md` in place. Append new `# ` sections; don't delete existing ones (agents may still reference old rules).
2. `git commit`. No network step.

## Entry format (single section inside a playbook file)

Each `# ` section is 2–5 sentences per sub-section minimum. Solution must include runnable code or exact commands.

```markdown
# {Short title}

## Problem
{What goes wrong and when}

## Solution
{Exact steps, commands, or code to fix it}

## Why
{Root cause — so agents can recognize variants of the same problem}
```

Special section headings the Orchestrator recognizes (see [orchestrator.md](orchestrator.md) Step 2 for the routing table):

- `# Role: Builder*` — injected into Builder's prompt only
- `# Role: Tester*` — injected into Tester's prompt only
- `# Role: Inspector*` — Inspector only
- `# Role: Orchestrator*` — Orchestrator only
- `# Template:*` — Tester only
- Everything else → general rules, injected into every agent's prompt

## Error handling

If `playbooks/registry.json` is missing or a referenced file can't be read, the Orchestrator warns with the missing path and proceeds without playbooks. The build loop does not abort — but agent output quality drops, so fix the path and re-run.
