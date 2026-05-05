#!/usr/bin/env bash
set -euo pipefail

# Create a branch, commit patched OpenAPI file, and open a PR on Bitbucket
# Required env vars:
#  BITBUCKET_OWNER, BITBUCKET_REPO, BASE_BRANCH (default: develop)
#  BITBUCKET_USERNAME, BITBUCKET_APP_PASSWORD
#  S3_BUCKET, S3_KEY (patched file in S3)
#  REPO_TARGET_PATH (path inside repo where openapi file should be written, e.g. openapi-definition.json)
#  PR_TITLE (optional), PR_DESCRIPTION (optional)

: "${BITBUCKET_OWNER:?}"
: "${BITBUCKET_REPO:?}"
BASE_BRANCH="${BASE_BRANCH:-develop}"
: "${BITBUCKET_USERNAME:?}"
: "${BITBUCKET_APP_PASSWORD:?}"
: "${S3_BUCKET:?}"
: "${S3_KEY:?}"
: "${REPO_TARGET_PATH:?}"
PR_TITLE="${PR_TITLE:-api-gw-update-$(date +%s)}"
PR_DESCRIPTION="${PR_DESCRIPTION:-Automated API Gateway template update}"

TMP_FILE="/tmp/patched-$(date +%s).json"
aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}" "${TMP_FILE}"

API_BASE="https://api.bitbucket.org/2.0/repositories/${BITBUCKET_OWNER}/${BITBUCKET_REPO}"

# Get base branch commit hash
echo "Fetching base branch ${BASE_BRANCH} info"
BASE_HASH=$(curl -s -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" "${API_BASE}/refs/branches/${BASE_BRANCH}" | jq -r .target.hash)
if [ -z "${BASE_HASH}" ] || [ "${BASE_HASH}" = "null" ]; then
  echo "Failed to get base branch hash" >&2
  exit 1
fi

NEW_BRANCH="api-gw-update-$(date +%s)"

echo "Creating branch ${NEW_BRANCH} from ${BASE_HASH}"
CREATE_BRANCH_PAYLOAD=$(jq -n --arg name "$NEW_BRANCH" --arg hash "$BASE_HASH" '{name:$name, target:{hash:$hash}}')
resp=$(curl -s -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" -X POST "${API_BASE}/refs/branches" -H 'Content-Type: application/json' -d "$CREATE_BRANCH_PAYLOAD")

# Commit patched file to new branch using Bitbucket "create/update file" endpoint
echo "Committing ${REPO_TARGET_PATH} to branch ${NEW_BRANCH}"
commit_resp=$(curl -s -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" -X POST "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_OWNER}/${BITBUCKET_REPO}/src" \
  -F "${REPO_TARGET_PATH}=@${TMP_FILE}" \
  -F "branch=${NEW_BRANCH}" \
  -F "message=Automated API GW patch from CI")

# Create pull request
echo "Creating pull request ${PR_TITLE}"
PR_PAYLOAD=$(jq -n --arg title "$PR_TITLE" --arg src "$NEW_BRANCH" --arg dst "$BASE_BRANCH" --arg body "$PR_DESCRIPTION" '{title:$title, source:{branch:{name:$src}}, destination:{branch:{name:$dst}}, description:$body, close_source_branch:false}')
pr_resp=$(curl -s -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" -X POST "${API_BASE}/pullrequests" -H 'Content-Type: application/json' -d "$PR_PAYLOAD")

echo "PR response:"
echo "$pr_resp" | jq .

rm -f "${TMP_FILE}"
