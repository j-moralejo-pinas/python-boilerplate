#!/bin/bash
# Setup branch protection rulesets
# Usage: setup-rulesets.sh <repo_slug> <workflow_type>
# Example: setup-rulesets.sh owner/repo gitflow

set -euo pipefail

REPO_SLUG="${1:?Repository slug is required}"
WORKFLOW_TYPE="${2:?Workflow type is required (gitflow or github_flow)}"

echo "Setting up rulesets for $REPO_SLUG with workflow type: $WORKFLOW_TYPE..."

API=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

find_ruleset_id_by_name() {
  local NAME="$1"
  gh api "/repos/$REPO_SLUG/rulesets" "${API[@]}" \
    | jq -r ".[] | select(.name==\"$NAME\") | .id" | head -n1
}

mk_checks_json() {
  jq -R -s 'split("\n") | map(select(length>0)) | map({context:.})'
}

replace_ruleset() {
  local NAME="$1" BRANCH="$2" ALLOWED_MERGES_JSON="$3"; shift 3
  local CHECKS_LIST=("$@")

  local CHECKS_JSON
  CHECKS_JSON=$(printf '%s\n' "${CHECKS_LIST[@]}" | mk_checks_json)

  local BODY
  BODY=$(jq -n \
    --arg name "$NAME" \
    --arg branch "refs/heads/$BRANCH" \
    --argjson allowed "$ALLOWED_MERGES_JSON" \
    --argjson checks "$CHECKS_JSON" '
    {
      name: $name,
      target: "branch",
      enforcement: "active",
      conditions: { ref_name: { include: [$branch], exclude: [] } },
      rules: [
        { "type": "deletion" },
        {
          "type": "pull_request",
          "parameters": {
            "dismiss_stale_reviews_on_push": true,
            "require_code_owner_review": true,
            "required_approving_review_count": 0,
            "required_review_thread_resolution": true,
            "require_last_push_approval": false,
            "allowed_merge_methods": $allowed
          }
        },
        {
          "type": "required_status_checks",
          "parameters": {
            "do_not_enforce_on_create": false,
            "required_status_checks": $checks,
            "strict_required_status_checks_policy": true
          }
        },
        { "type": "non_fast_forward" }
      ]
    }')

  local ID
  ID=$(find_ruleset_id_by_name "$NAME" || true)
  if [ -n "${ID:-}" ]; then
    gh api -i -X DELETE "/repos/$REPO_SLUG/rulesets/$ID" "${API[@]}" || true
  fi

  gh api -i -X POST "/repos/$REPO_SLUG/rulesets" "${API[@]}" \
    --input <(printf '%s' "$BODY")
}

if [[ "$WORKFLOW_TYPE" == "gitflow" ]]; then
  echo "Configuring rulesets for GitFlow workflow"

  # Main: Merge only, checks: check-source-branch, format, code-quality, test
  replace_ruleset "Main" "main"  "$(jq -n '["merge"]')" \
    "call-reusable / check-source-branch" "call-reusable / format" "call-reusable / code-quality" "call-reusable / test"

  # Dev: Merge + Squash, checks: format, test
  replace_ruleset "Dev"  "dev"   "$(jq -n '["merge","squash"]')" \
    "call-reusable / format" "call-reusable / test"

else
  echo "Configuring rulesets for GitHub Flow workflow"

  # Main: Allow all merge types, checks: check-source-branch, format, code-quality, test
  replace_ruleset "Main" "main"  "$(jq -n '["merge","squash","rebase"]')" \
    "call-reusable / check-source-branch" "call-reusable / format" "call-reusable / code-quality" "call-reusable / test"

  # Remove any existing Dev ruleset since it's not needed for GitHub Flow
  DEV_RULESET_ID=$(find_ruleset_id_by_name "Dev" || true)
  if [ -n "${DEV_RULESET_ID:-}" ]; then
    echo "Removing Dev ruleset (not needed for GitHub Flow)"
    gh api -i -X DELETE "/repos/$REPO_SLUG/rulesets/$DEV_RULESET_ID" "${API[@]}" || true
  fi
fi

echo "✓ Rulesets configured"
