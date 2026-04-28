#!/usr/bin/env bash
#
# Create and push an annotated Git tag for the vulcan-file LuaSkill release.
# 创建并推送用于 vulcan-file LuaSkill 发布的带注释 Git 标签。

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: ./scripts/tag_release.sh <version>"
  echo "用法：./scripts/tag_release.sh <版本号>"
  exit 1
fi

version="$1"
if [[ "$version" == v* ]]; then
  tag="$version"
else
  tag="v$version"
fi

echo "Creating annotated tag: $tag"
git tag -a "$tag" -m "Release $tag"

echo "Pushing tag to origin: $tag"
git push origin "$tag"
