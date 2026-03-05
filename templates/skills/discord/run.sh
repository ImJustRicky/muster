#!/usr/bin/env bash
set -eo pipefail

# Discord notification skill for muster
# Sends deploy, rollback, and fleet notifications as rich embeds to a Discord channel.
# Uses Discord API v10 — https://discord.com/developers/docs/resources/message
#
# Required config:
#   MUSTER_DISCORD_BOT_TOKEN  — Bot token (discord.com/developers/applications)
#   MUSTER_DISCORD_CHANNEL_ID — Target channel ID
#
# Supports all deploy hooks and fleet hooks.
# Per-fleet config lets you send to different channels per fleet.

if [[ -z "${MUSTER_DISCORD_BOT_TOKEN:-}" ]]; then
  echo "[discord] No bot token configured, skipping."
  exit 0
fi

if [[ -z "${MUSTER_DISCORD_CHANNEL_ID:-}" ]]; then
  echo "[discord] No channel ID configured, skipping."
  exit 0
fi

# --- Context ---

HOOK="${MUSTER_HOOK:-unknown}"
STATUS="${MUSTER_DEPLOY_STATUS:-unknown}"
SERVICE="${MUSTER_SERVICE_NAME:-${MUSTER_SERVICE:-}}"
FLEET="${MUSTER_FLEET_NAME:-}"
MACHINE="${MUSTER_FLEET_MACHINE:-}"
HOST="${MUSTER_FLEET_HOST:-}"
STRATEGY="${MUSTER_FLEET_STRATEGY:-}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# Discord embed colors (decimal)
C_GREEN=3066993
C_RED=15158332
C_ORANGE=15105570
C_BLUE=3447003
C_GREY=9807270

COLOR=$C_GREY
TITLE=""
DESC=""

# --- Build notification based on hook type ---

case "$HOOK" in
  # Fleet-level hooks
  fleet-deploy-start)
    COLOR=$C_BLUE
    TITLE="Fleet deploy started: ${FLEET}"
    DESC="Strategy: ${STRATEGY}"
    ;;
  fleet-deploy-end)
    if [[ "$STATUS" == "ok" ]]; then
      COLOR=$C_GREEN; TITLE="Fleet deploy complete: ${FLEET}"
    else
      COLOR=$C_RED; TITLE="Fleet deploy FAILED: ${FLEET}"
    fi
    DESC="Strategy: ${STRATEGY}"
    ;;
  fleet-machine-deploy-start)
    COLOR=$C_BLUE
    TITLE="Deploying to ${MACHINE}"
    DESC="Host: ${HOST}"
    ;;
  fleet-machine-deploy-end)
    if [[ "$STATUS" == "ok" ]]; then
      COLOR=$C_GREEN; TITLE="Deployed to ${MACHINE}"
    else
      COLOR=$C_RED; TITLE="Deploy FAILED: ${MACHINE}"
    fi
    DESC="Host: ${HOST}"
    ;;
  fleet-rollback-start)
    COLOR=$C_ORANGE
    TITLE="Fleet rollback started: ${FLEET}"
    ;;
  fleet-rollback-end)
    if [[ "$STATUS" == "ok" ]]; then
      COLOR=$C_GREEN; TITLE="Fleet rollback complete: ${FLEET}"
    else
      COLOR=$C_RED; TITLE="Fleet rollback FAILED: ${FLEET}"
    fi
    ;;
  # Standard deploy/rollback hooks
  post-deploy)
    case "$STATUS" in
      success) COLOR=$C_GREEN;  TITLE="Deployed ${SERVICE}" ;;
      failed)  COLOR=$C_RED;    TITLE="Deploy FAILED: ${SERVICE}" ;;
      skipped) COLOR=$C_ORANGE; TITLE="Deploy skipped: ${SERVICE}" ;;
      *)       COLOR=$C_GREY;   TITLE="Deploy ${STATUS}: ${SERVICE}" ;;
    esac
    ;;
  post-rollback)
    case "$STATUS" in
      success) COLOR=$C_GREEN;  TITLE="Rolled back ${SERVICE}" ;;
      failed)  COLOR=$C_RED;    TITLE="Rollback FAILED: ${SERVICE}" ;;
      *)       COLOR=$C_ORANGE; TITLE="Rollback ${STATUS}: ${SERVICE}" ;;
    esac
    ;;
  *)
    TITLE="${HOOK}: ${SERVICE:-${FLEET:-unknown}}"
    ;;
esac

# --- Build embed JSON ---

# Escape double quotes for JSON safety
_esc() { printf '%s' "$1" | sed 's/"/\\"/g'; }

EMBED="{\"title\":\"$(_esc "$TITLE")\",\"color\":${COLOR},\"timestamp\":\"${TIMESTAMP}\""

if [[ -n "$DESC" ]]; then
  EMBED="${EMBED},\"description\":\"$(_esc "$DESC")\""
fi

# Add fleet footer for fleet events
if [[ -n "$FLEET" ]]; then
  FOOTER="Fleet: ${FLEET}"
  [[ -n "$STRATEGY" ]] && FOOTER="${FOOTER} | ${STRATEGY}"
  EMBED="${EMBED},\"footer\":{\"text\":\"$(_esc "$FOOTER")\"}"
fi

EMBED="${EMBED}}"

# --- Send to Discord API v10 ---

if ! curl -sf -X POST \
  "https://discord.com/api/v10/channels/${MUSTER_DISCORD_CHANNEL_ID}/messages" \
  -H "Authorization: Bot ${MUSTER_DISCORD_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"embeds\":[${EMBED}]}" \
  > /dev/null 2>&1; then
  echo "[discord] Failed to send notification (curl error). Continuing."
fi

exit 0
