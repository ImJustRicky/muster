#!/usr/bin/env bash
set -eo pipefail

# Slack notification skill for muster
# Sends deploy, rollback, and fleet notifications via Slack Incoming Webhook.
# Uses Block Kit (modern) — https://docs.slack.dev/block-kit
#
# Required config:
#   MUSTER_SLACK_WEBHOOK — Slack incoming webhook URL
#
# Supports all deploy hooks and fleet hooks.
# Per-fleet config lets you send to different Slack channels per fleet.

if [[ -z "${MUSTER_SLACK_WEBHOOK:-}" ]]; then
  echo "[slack] No webhook URL configured, skipping."
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

# Emoji + text based on event type
EMOJI=""
TEXT=""
CONTEXT=""

case "$HOOK" in
  # Fleet hooks
  fleet-deploy-start)
    EMOJI=":rocket:"
    TEXT="Fleet deploy started: *${FLEET}* (${STRATEGY})"
    ;;
  fleet-deploy-end)
    if [[ "$STATUS" == "ok" ]]; then
      EMOJI=":white_check_mark:"; TEXT="Fleet deploy complete: *${FLEET}*"
    else
      EMOJI=":x:"; TEXT="Fleet deploy FAILED: *${FLEET}*"
    fi
    CONTEXT="Strategy: ${STRATEGY}"
    ;;
  fleet-machine-deploy-start)
    EMOJI=":gear:"
    TEXT="Deploying to *${MACHINE}*"
    CONTEXT="Host: ${HOST}"
    ;;
  fleet-machine-deploy-end)
    if [[ "$STATUS" == "ok" ]]; then
      EMOJI=":white_check_mark:"; TEXT="Deployed to *${MACHINE}*"
    else
      EMOJI=":x:"; TEXT="Deploy FAILED: *${MACHINE}*"
    fi
    CONTEXT="Host: ${HOST}"
    ;;
  fleet-rollback-start)
    EMOJI=":rewind:"
    TEXT="Fleet rollback started: *${FLEET}*"
    ;;
  fleet-rollback-end)
    if [[ "$STATUS" == "ok" ]]; then
      EMOJI=":white_check_mark:"; TEXT="Fleet rollback complete: *${FLEET}*"
    else
      EMOJI=":x:"; TEXT="Fleet rollback FAILED: *${FLEET}*"
    fi
    ;;
  # Standard hooks
  post-deploy)
    case "$STATUS" in
      success) EMOJI=":white_check_mark:"; TEXT="Deployed *${SERVICE}*" ;;
      failed)  EMOJI=":x:";               TEXT="Deploy FAILED: *${SERVICE}*" ;;
      skipped) EMOJI=":fast_forward:";     TEXT="Deploy skipped: *${SERVICE}*" ;;
      *)       EMOJI=":grey_question:";    TEXT="Deploy ${STATUS}: *${SERVICE}*" ;;
    esac
    ;;
  post-rollback)
    case "$STATUS" in
      success) EMOJI=":rewind:";           TEXT="Rolled back *${SERVICE}*" ;;
      failed)  EMOJI=":x:";               TEXT="Rollback FAILED: *${SERVICE}*" ;;
      *)       EMOJI=":grey_question:";    TEXT="Rollback ${STATUS}: *${SERVICE}*" ;;
    esac
    ;;
  *)
    EMOJI=":information_source:"
    TEXT="${HOOK}: *${SERVICE:-${FLEET:-unknown}}*"
    ;;
esac

# --- Build Block Kit payload ---

_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Main section block with emoji + text
BLOCKS="[{\"type\":\"section\",\"text\":{\"type\":\"mrkdwn\",\"text\":\"$(_esc "${EMOJI} ${TEXT}")\"}}"

# Add context block for fleet info
if [[ -n "$FLEET" || -n "$CONTEXT" ]]; then
  CTX_PARTS=""
  if [[ -n "$FLEET" ]]; then
    CTX_PARTS="{\"type\":\"mrkdwn\",\"text\":\"Fleet: *$(_esc "$FLEET")*\"}"
  fi
  if [[ -n "$CONTEXT" ]]; then
    [[ -n "$CTX_PARTS" ]] && CTX_PARTS="${CTX_PARTS},"
    CTX_PARTS="${CTX_PARTS}{\"type\":\"mrkdwn\",\"text\":\"$(_esc "$CONTEXT")\"}"
  fi
  BLOCKS="${BLOCKS},{\"type\":\"context\",\"elements\":[${CTX_PARTS}]}"
fi

BLOCKS="${BLOCKS}]"

# Fallback text for notifications (no markdown)
FALLBACK="${EMOJI} ${TEXT}"
FALLBACK="${FALLBACK//\*/}"

PAYLOAD="{\"text\":\"$(_esc "$FALLBACK")\",\"blocks\":${BLOCKS}}"

# --- Send to Slack ---

if ! curl -sf -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$MUSTER_SLACK_WEBHOOK" > /dev/null 2>&1; then
  echo "[slack] Failed to send notification (curl error). Continuing."
fi

exit 0
