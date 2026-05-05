#!/usr/bin/env bash
set -euo pipefail

# Export OpenAPI template from Bitbucket and upload to S3
# Required env vars:
#  BITBUCKET_OWNER, BITBUCKET_REPO, BITBUCKET_BRANCH (default: develop)
#  BITBUCKET_USERNAME, BITBUCKET_APP_PASSWORD
#  FILE_PATH_IN_REPO (path to openapi JSON in the repo)
#  S3_BUCKET, S3_KEY (destination key, e.g. templates/private-qa.json)

: "${BITBUCKET_OWNER:?}"
: "${BITBUCKET_REPO:?}"
BITBUCKET_BRANCH="${BITBUCKET_BRANCH:-develop}"
: "${BITBUCKET_USERNAME:?}"
: "${BITBUCKET_APP_PASSWORD:?}"
: "${FILE_PATH_IN_REPO:?}"
: "${S3_BUCKET:?}"
: "${S3_KEY:?}"

TMP_FILE="/tmp/openapi-$(date +%s).json"
RAW_URL="https://api.bitbucket.org/2.0/repositories/${BITBUCKET_OWNER}/${BITBUCKET_REPO}/src/${BITBUCKET_BRANCH}/${FILE_PATH_IN_REPO}"

echo "Fetching ${RAW_URL}"
curl -fSL -u "${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}" "${RAW_URL}" -o "${TMP_FILE}"

echo "Uploading to s3://${S3_BUCKET}/${S3_KEY}"
aws s3 cp "${TMP_FILE}" "s3://${S3_BUCKET}/${S3_KEY}"

echo "Done. Uploaded to s3://${S3_BUCKET}/${S3_KEY}"
rm -f "${TMP_FILE}"
