# Playbook Management

*Reference for creating, updating, and managing playbook gists. Loaded by the Orchestrator when playbook operations are needed.*

## Registry

Default registry gist: `bca7073d567ca8b7ba79ff4bad5fb2c5`

**Local override:** If `.autocraft` exists at the repo root, read `registry_gist_id` from it:

```json
{
  "registry_gist_id": "bca7073d567ca8b7ba79ff4bad5fb2c5"
}
```

Resolution order:
1. `.autocraft` file in repo root → use `registry_gist_id`
2. No `.autocraft` file → use default `bca7073d567ca8b7ba79ff4bad5fb2c5`

Registry format:
```json
{
  "playbooks": [
    {
      "platform": "macos",
      "gist_id": "84a5c108d5742c850704a5088a3f4cbf",
      "description": "Xcode, SwiftUI, XCUITest, codesign, ScreenCaptureKit"
    }
  ]
}
```

## Commands

```bash
# Read the registry
gh gist view <registry-id> -f playbooks.json

# Update the registry (non-interactive)
gh api --method PATCH /gists/<registry-id> \
  -f "files[playbooks.json][content]=$(cat /tmp/playbooks.json)"

# List files in a playbook
gh gist view <gist-id> --files

# Read a specific entry
gh gist view <gist-id> -f <filename>

# Add or update an entry (write file locally, then push)
gh api --method PATCH /gists/<gist-id> \
  -f "files[<filename>.md][content]=$(cat /tmp/<filename>.md)"

# Delete an entry
gh api --method PATCH /gists/<gist-id> \
  -f "files[<filename>.md]="
```

## Creating a New Playbook

1. **Gather content** — ask the user what entries to include, or accept content they provide
2. **Write entry files** to `/tmp/` using kebab-case names: `{category}-{short-name}.md` (e.g., `networking-cors-preflight.md`, `testing-playwright-selectors.md`)
3. **Create the gist**:
   ```bash
   gh gist create --public -d "Autocraft playbook: {platform}" /tmp/entry1.md /tmp/entry2.md ...
   # Capture the gist ID from the output URL (last path segment)
   ```
4. **Register the playbook** — fetch the registry, add the new entry, push back:
   ```bash
   gh gist view <registry-id> -f playbooks.json > /tmp/playbooks.json
   # Add new entry to the playbooks array (use jq or manual edit)
   gh api --method PATCH /gists/<registry-id> \
     -f "files[playbooks.json][content]=$(cat /tmp/playbooks.json)"
   ```
   Platform keys: lowercase, no spaces (e.g., `macos`, `web`, `ios`, `android`, `go`, `python`)
5. **Clean up** temp files in `/tmp/`

## Updating an Existing Playbook

1. **Resolve the gist ID** — look up the platform in the registry to get its `gist_id`
2. **Fetch current content** (if updating):
   ```bash
   gh gist view <gist-id> -f <filename>.md > /tmp/<filename>.md
   ```
3. **Write or edit** the entry file in `/tmp/`
4. **Push** — PATCH adds new files or overwrites existing ones:
   ```bash
   gh api --method PATCH /gists/<gist-id> \
     -f "files[<filename>.md][content]=$(cat /tmp/<filename>.md)"
   ```
   Multiple files can be pushed in a single PATCH by adding more `-f` flags.
5. **Clean up** temp files in `/tmp/`

## Playbook Entry Format

Each entry: 2-5 sentences per section minimum, Solution must include runnable code or exact commands.

```markdown
# {Short title}

## Problem
{What goes wrong and when}

## Solution
{Exact steps, commands, or code to fix it}

## Why
{Root cause — so agents can recognize variants of the same problem}
```

## Selecting Playbooks for a Project

The Orchestrator loads ALL registered playbooks at startup. If the project only uses one platform, only that playbook's entries are included in agent prompts.

**Error handling:** If the registry gist fetch fails (network, auth), warn the user and proceed without playbooks. Do not abort the build loop.

## Auto-Fork on Permission Failure

Only the gist owner can update the registry. When `gh api PATCH` fails with 404 or 403, automatically fork and switch:

```bash
# 1. Fork the registry
FORK_URL=$(gh gist fork <registry-id> 2>&1)
FORK_ID=$(echo "$FORK_URL" | grep -oE '[a-f0-9]{20,}' | tail -1)

# 2. Save fork ID to .autocraft
echo "{\"registry_gist_id\": \"$FORK_ID\"}" > .autocraft

# 3. Retry the update with the fork
gh api --method PATCH /gists/$FORK_ID \
  -f "files[playbooks.json][content]=$(cat /tmp/playbooks.json)"

# 4. Commit .autocraft
git add .autocraft && git commit -m "Use forked playbook registry: $FORK_ID"
```

This is transparent — future sessions read `.autocraft` and use the fork automatically.
