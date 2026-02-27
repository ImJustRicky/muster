# Creating Muster Skills

Skills are community addons that extend muster with new capabilities. A skill is just a folder with a `skill.json` manifest and a `run.sh` script.

## Structure

```
muster-skill-yourname/
├── skill.json    ← manifest (required)
├── run.sh        ← entry point (required, must be executable)
└── lib/          ← optional helper scripts
```

## skill.json

```json
{
  "name": "ssl",
  "version": "1.0.0",
  "description": "Auto-manage SSL certificates via Let's Encrypt",
  "author": "yourname",
  "hooks": ["post-deploy"],
  "requires": ["certbot"]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Short name used in `muster skill run <name>` |
| `version` | yes | Semver version string |
| `description` | yes | One-line description shown in `muster skill list` |
| `author` | no | Who made it |
| `hooks` | no | When this skill can run: `pre-deploy`, `post-deploy`, `pre-rollback`, `post-rollback` |
| `requires` | no | External commands that must be available (muster warns if missing) |

## run.sh

Your skill's entry point. It receives context via environment variables:

```bash
#!/usr/bin/env bash
# run.sh — your skill logic

# Available environment variables:
#   MUSTER_PROJECT_DIR   — path to the project root
#   MUSTER_CONFIG_FILE   — path to deploy.json
#   MUSTER_SERVICE       — current service name (if run per-service)
#   MUSTER_HOOK          — which hook triggered this (e.g. "post-deploy")

echo "Running SSL skill for ${MUSTER_SERVICE:-all services}"

# Your logic here
certbot renew --quiet || exit 1
```

Make sure `run.sh` is executable:

```bash
chmod +x run.sh
```

Exit codes:
- `0` — success
- `1` — failure (muster reports the error)

## Creating a Skill

The fastest way to start:

```bash
muster skill create my-skill
```

This scaffolds `~/.muster/skills/my-skill/` with a ready-to-edit `skill.json` and executable `run.sh` stub. Edit the files, add hooks, and test with `muster skill run my-skill`.

## Hooks

Skills that declare hooks in `skill.json` are automatically triggered during deploy and rollback:

| Hook | When it runs |
|------|-------------|
| `pre-deploy` | Before each service deploys |
| `post-deploy` | After each service deploys successfully |
| `pre-rollback` | Before a service rollback |
| `post-rollback` | After a service rollback succeeds |

Hook execution is **non-fatal** — if a skill fails, muster warns and continues.

## Installing

Users install your skill from a git repo:

```bash
muster skill add https://github.com/yourname/muster-skill-ssl
```

Or from a local path:

```bash
muster skill add ./my-local-skill
```

Skills are installed to `~/.muster/skills/<name>/`.

## Example: Slack Notifications

```
muster-skill-notify/
├── skill.json
└── run.sh
```

**skill.json:**

```json
{
  "name": "notify",
  "version": "1.0.0",
  "description": "Send deploy notifications to Slack",
  "hooks": ["post-deploy", "post-rollback"],
  "requires": ["curl"]
}
```

**run.sh:**

```bash
#!/usr/bin/env bash
WEBHOOK_URL="${MUSTER_NOTIFY_WEBHOOK:-}"

if [[ -z "$WEBHOOK_URL" ]]; then
  echo "Set MUSTER_NOTIFY_WEBHOOK environment variable"
  exit 1
fi

MESSAGE="Deployed ${MUSTER_SERVICE:-project} (${MUSTER_HOOK})"

curl -s -X POST "$WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d "{\"text\": \"${MESSAGE}\"}" >/dev/null

echo "Notification sent"
```

## Naming Convention

If publishing to GitHub, name your repo `muster-skill-<name>`. The `muster-skill-` prefix is automatically stripped during install.

## Testing Your Skill

```bash
# Create a new skill
muster skill create my-skill

# Or install from local path
muster skill add ./your-skill-folder

# Run it
muster skill run my-skill

# Check it shows up
muster skill list

# Remove it
muster skill remove my-skill
```
