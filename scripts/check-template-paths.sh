#!/usr/bin/env bash
# Checks that every local path a template hands to aws cloudformation package
# (ContentUri, ReadmeUrl, LicenseUrl) exists relative to the template itself,
# which is how package resolves them.
#
# Usage: scripts/check-template-paths.sh <template.yaml>
set -euo pipefail

template=$1
dir=$(dirname "$template")
status=0
found=0

while read -r key value; do
  found=$((found + 1))
  case "$value" in
    *://*) continue ;; # already an S3 or web URL
  esac
  if [ -e "$dir/$value" ]; then
    echo "ok: $key $value"
  else
    echo "FAIL: $key '$value' does not exist relative to $template" >&2
    status=1
  fi
done < <(sed -nE 's/^[[:space:]]*(ContentUri|ReadmeUrl|LicenseUrl):[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1 \2/p' "$template")

if [ "$found" -ne 3 ]; then
  echo "FAIL: expected ContentUri, ReadmeUrl and LicenseUrl in $template, found $found" >&2
  exit 1
fi
exit "$status"
