#!/bin/bash
set -euo pipefail

# Define variables
BUCKET="ami-manifests-arkinfotech24"
PREFIX="arkinfotech24"
VERSION="v1.0.10"  # GitHub tags must start with 'v' for semantic release
REPO_ROOT="/home/sysadmin/packer-ami-pipeline/packer"
LOG_DIR="$REPO_ROOT/logs"
MANIFEST_DIR="$REPO_ROOT/manifests"
GH_REPO="arkinfotech24/Release"

echo "[UPLOAD] Starting artifact upload for version: $VERSION"

# Upload to S3
if [[ -f "$REPO_ROOT/manifest.json" ]]; then
  aws s3 cp "$REPO_ROOT/manifest.json" \
    s3://$BUCKET/$PREFIX/manifest-${VERSION}.json
else
  echo "[WARN] Missing: manifest.json"
fi

for distro in rhel9 ubuntu al2023; do
  LOG_PATH="$LOG_DIR/${distro}-${VERSION}.log"
  if [[ -f "$LOG_PATH" ]]; then
    aws s3 cp "$LOG_PATH" \
      s3://$BUCKET/$PREFIX/logs/${distro}-${VERSION}.log
  else
    echo "[WARN] Missing log: $LOG_PATH"
  fi
done

if [[ -d "$MANIFEST_DIR" ]]; then
  for distro in rhel9 ubuntu al2023; do
    MANIFEST_PATH="$MANIFEST_DIR/${distro}.json"
    if [[ -f "$MANIFEST_PATH" ]]; then
      aws s3 cp "$MANIFEST_PATH" \
        s3://$BUCKET/$PREFIX/manifests/${distro}-${VERSION}.json
    else
      echo "[WARN] Missing manifest: $MANIFEST_PATH"
    fi
  done
else
  echo "[INFO] Skipping manifest upload—directory not found: $MANIFEST_DIR"
fi

echo "[UPLOAD] ✅ All available artifacts uploaded to s3://$BUCKET/$PREFIX/"

# 🧩 GitHub Release Section
echo "[GITHUB] Creating release $VERSION on $GH_REPO"

# Create tag if not already present
if ! git rev-parse "$VERSION" >/dev/null 2>&1; then
  git tag -a "$VERSION" -m "Automated release $VERSION"
  git push origin "$VERSION"
fi

# Collect artifacts
ARTIFACTS=()
[[ -f "$REPO_ROOT/manifest.json" ]] && ARTIFACTS+=("$REPO_ROOT/manifest.json")
for distro in rhel9 ubuntu al2023; do
  [[ -f "$LOG_DIR/${distro}-${VERSION}.log" ]] && ARTIFACTS+=("$LOG_DIR/${distro}-${VERSION}.log")
  [[ -f "$MANIFEST_DIR/${distro}.json" ]] && ARTIFACTS+=("$MANIFEST_DIR/${distro}.json")
done

# Create GitHub release
gh release create "$VERSION" "${ARTIFACTS[@]}" \
  --repo "$GH_REPO" \
  --title "Release $VERSION" \
  --notes "Automated release of AMI manifests and logs for $VERSION"

echo "[GITHUB] ✅ Release $VERSION published to https://github.com/$GH_REPO/releases/tag/$VERSION"

