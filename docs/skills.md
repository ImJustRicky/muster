# Creating Muster Skills

Skills are addons that extend muster with new capabilities — notifications, monitoring, automation, anything. A skill is just a folder with a `skill.json` manifest and a `run.sh` script.

Browse official skills: [muster-skills marketplace](https://github.com/ImJustRicky/muster-skills)

## Quick Start

```bash
muster skill create my-skill
# Edit ~/.muster/skills/my-skill/skill.json and run.sh
muster skill run my-skill
```

## Structure

```
my-skill/
├── skill.json    ← manifest (required)
├── run.sh        ← entry point (required, executable)
└── lib/          ← optional helper scripts
```

## skill.json

```json
{
  "name": "my-skill",
  "version": "1.0.0",
  "description": "What this skill does in one line",
  "author": "yourname",
  "hooks": ["post-deploy", "post-rollback"],
  "requires": ["curl"],
  "config": [
    {
      "key": "MY_SKILL_API_KEY",
      "label": "API Key",
      "hint": "Where to find this value",
      "secret": true
    },
    {
      "key": "MY_SKILL_URL",
      "label": "Endpoint URL",
      "hint": "e.g. https://example.com/webhook"
    }
  ]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Short name, used in `muster skill run <name>` |
| `version` | yes | Semver version string |
| `description` | yes | One-line description shown in `muster skill list` and marketplace |
| `author` | no | Who made it |
| `hooks` | no | When to auto-run: `pre-deploy`, `post-deploy`, `pre-rollback`, `post-rollback` |
| `requires` | no | External commands that must be available (muster warns if missing) |
| `config` | no | Array of configuration values the user needs to provide (see below) |

### Config

The `config` array defines values the user must provide for the skill to work (API keys, webhook URLs, etc.). Each entry:

| Field | Required | Description |
|-------|----------|-------------|
| `key` | yes | Environment variable name (e.g. `MY_SKILL_API_KEY`) |
| `label` | no | Human-readable label shown in the configure TUI |
| `hint` | no | Help text (where to find the value, example format) |
| `secret` | no | If `true`, input is hidden and stored value is masked |

Users configure skills with `muster skill configure <name>`, which prompts for each value and saves them to `config.env` in the skill directory. Values are automatically loaded as environment variables before your `run.sh` executes.

## run.sh

Your skill's entry point. It receives context via environment variables:

```bash
#!/usr/bin/env bash
set -eo pipefail

# Environment variables available to your skill:
#
#   MUSTER_SERVICE        — service key (e.g. "api")
#   MUSTER_SERVICE_NAME   — display name (e.g. "API Server")
#   MUSTER_HOOK           — which hook triggered this (e.g. "post-deploy")
#   MUSTER_DEPLOY_STATUS  — outcome: "success", "failed", or "skipped"
#   MUSTER_PROJECT_DIR    — path to the project root
#   MUSTER_CONFIG_FILE    — path to deploy.json
#
# Plus any values from your config[] (loaded from config.env)

# Example: send different notifications based on status
case "${MUSTER_HOOK}:${MUSTER_DEPLOY_STATUS}" in
  post-deploy:success)
    echo "Deploy succeeded for ${MUSTER_SERVICE_NAME}"
    ;;
  post-deploy:failed)
    echo "Deploy FAILED for ${MUSTER_SERVICE_NAME}"
    ;;
  post-deploy:skipped)
    echo "Deploy skipped for ${MUSTER_SERVICE_NAME}"
    ;;
esac
```

Make sure `run.sh` is executable: `chmod +x run.sh`

Exit codes:
- `0` — success
- Non-zero — failure (muster warns and continues, deploy is not blocked)

## Hooks

Skills that declare hooks in `skill.json` can auto-run during deploy and rollback. The user must **enable** the skill first:

```bash
muster skill configure my-skill   # fill in config values
muster skill enable my-skill      # turn on auto-run
```

| Hook | When it fires |
|------|---------------|
| `pre-deploy` | Before each service deploys |
| `post-deploy` | After each service deploy (success, failed, or skipped) |
| `pre-rollback` | Before a service rollback |
| `post-rollback` | After a service rollback (success or failed) |

Hook execution is **non-fatal** — if a skill fails, muster warns and continues. Deploys are never blocked by skill errors.

### Deploy Status

`post-deploy` and `post-rollback` hooks receive `MUSTER_DEPLOY_STATUS`:

| Status | Meaning |
|--------|---------|
| `success` | Deploy/rollback completed successfully |
| `failed` | Deploy/rollback failed (user chose rollback, skip, or abort) |
| `skipped` | User chose to skip this service |

Use this to send different notifications for success vs failure.

### Enabled vs Manual

- **Enabled** — skill auto-runs on its declared hooks during deploy/rollback
- **Manual** — skill only runs when the user clicks "Run" in the dashboard or uses `muster skill run`

Skills start as manual after install. Users enable them after configuring.

## Skill Lifecycle

```
Install → Configure → Enable → Auto-runs on deploy/rollback
                              → Or run manually anytime
```

Commands:

```bash
muster skill marketplace          # browse and install from official registry
muster skill add <url-or-path>    # install from git URL or local path
muster skill configure <name>     # set API keys, webhooks, etc.
muster skill enable <name>        # turn on auto-run for hooks
muster skill disable <name>       # turn off auto-run (manual only)
muster skill run <name>           # run manually
muster skill list                 # show installed skills with status
muster skill remove <name>        # uninstall
muster skill create <name>        # scaffold a new skill
```

## Publishing Your Skill

### Option A: Own repo

Name your repo `muster-skill-<name>`. The `muster-skill-` prefix is auto-stripped during install.

```bash
# Users install with:
muster skill add https://github.com/yourname/muster-skill-ssl
```

### Option B: Submit to the official marketplace

Add your skill to [muster-skills](https://github.com/ImJustRicky/muster-skills):

1. Fork the repo
2. Add your skill folder (`my-skill/skill.json` + `my-skill/run.sh`)
3. Add an entry to `registry.json`
4. Open a PR

Once merged, your skill appears in `muster skill marketplace` for everyone.

## Example: Discord Notifications

A complete skill that sends context-aware deploy notifications:

**skill.json:**

```json
{
  "name": "discord",
  "version": "1.0.0",
  "description": "Send deploy notifications to Discord",
  "hooks": ["post-deploy", "post-rollback"],
  "requires": ["curl"],
  "config": [
    {
      "key": "MUSTER_DISCORD_BOT_TOKEN",
      "label": "Discord Bot Token",
      "hint": "discord.com/developers/applications > Bot > Token",
      "secret": true
    },
    {
      "key": "MUSTER_DISCORD_CHANNEL_ID",
      "label": "Channel ID",
      "hint": "Right-click channel > Copy Channel ID"
    }
  ]
}
```

**run.sh:**

```bash
#!/usr/bin/env bash
set -eo pipefail

[[ -z "${MUSTER_DISCORD_BOT_TOKEN:-}" ]] && exit 0
[[ -z "${MUSTER_DISCORD_CHANNEL_ID:-}" ]] && exit 0

SERVICE="${MUSTER_SERVICE_NAME:-${MUSTER_SERVICE:-unknown}}"
STATUS="${MUSTER_DEPLOY_STATUS:-unknown}"

case "${MUSTER_HOOK}:${STATUS}" in
  post-deploy:success) COLOR=3066993;  TITLE="Deployed ${SERVICE}" ;;
  post-deploy:failed)  COLOR=15158332; TITLE="Deploy FAILED: ${SERVICE}" ;;
  post-rollback:*)     COLOR=15105570; TITLE="Rolled back ${SERVICE}" ;;
  *)                   COLOR=9807270;  TITLE="${MUSTER_HOOK}: ${SERVICE}" ;;
esac

curl -sf -X POST \
  "https://discord.com/api/v10/channels/${MUSTER_DISCORD_CHANNEL_ID}/messages" \
  -H "Authorization: Bot ${MUSTER_DISCORD_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"embeds\":[{\"title\":\"${TITLE}\",\"color\":${COLOR}}]}" \
  > /dev/null 2>&1 || true

exit 0
```

## Testing Your Skill

```bash
# Scaffold and edit
muster skill create my-skill

# Test manually
muster skill run my-skill

# Test with deploy context
MUSTER_SERVICE=api MUSTER_SERVICE_NAME="API Server" \
  MUSTER_HOOK=post-deploy MUSTER_DEPLOY_STATUS=success \
  ~/.muster/skills/my-skill/run.sh

# Test failure notification
MUSTER_SERVICE=api MUSTER_SERVICE_NAME="API Server" \
  MUSTER_HOOK=post-deploy MUSTER_DEPLOY_STATUS=failed \
  ~/.muster/skills/my-skill/run.sh

# Check it shows up
muster skill list
```
