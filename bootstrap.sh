#!/usr/bin/env sh
set -eu

REPO_SLUG="${AI_REVIEW_HOOK_REPO:-youqianHan/git-ai-review-hook}"
HOST_NAME="${AI_REVIEW_HOOK_HOST:-github}"
VERSION="${AI_REVIEW_HOOK_VERSION:-latest}"
LOCAL_ZIP="${AI_REVIEW_HOOK_ZIP:-}"
INSTALL_SCOPE="${AI_REVIEW_HOOK_SCOPE:-}"
LATEST_GITEE_VERSION="v0.1.5"

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$INSTALL_SCOPE" ]; then
  default_scope="local"
  [ -z "$repo_root" ] && default_scope="global"
  printf '%s [%s]: ' "Install scope (local global)" "$default_scope" >&2
  IFS= read -r INSTALL_SCOPE || INSTALL_SCOPE=""
  [ -n "$INSTALL_SCOPE" ] || INSTALL_SCOPE="$default_scope"
fi
case "$INSTALL_SCOPE" in
  local|global) ;;
  *) fail "Invalid AI_REVIEW_HOOK_SCOPE: $INSTALL_SCOPE. Use local or global." ;;
esac
case "$HOST_NAME" in
  github|gitee) ;;
  *) fail "Invalid AI_REVIEW_HOOK_HOST: $HOST_NAME. Use github or gitee." ;;
esac
if [ -z "$repo_root" ] && [ "$INSTALL_SCOPE" != "global" ]; then
  fail "Run this installer inside a Git repository, or set AI_REVIEW_HOOK_SCOPE=global."
fi
[ -n "$repo_root" ] && cd "$repo_root"

if ! need_cmd unzip; then
  printf '%s\n' "unzip is required." >&2
  printf '%s\n' "macOS: xcode-select --install  OR  brew install unzip" >&2
  printf '%s\n' "Linux: install unzip with your package manager." >&2
  exit 1
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t ai-review-hook)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
zip_file="$tmp_dir/git-ai-review-hook.zip"

if [ -n "$LOCAL_ZIP" ]; then
  [ -f "$LOCAL_ZIP" ] || fail "Local zip not found: $LOCAL_ZIP"
  cp "$LOCAL_ZIP" "$zip_file"
else
  if [ "$HOST_NAME" = "gitee" ]; then
    archive_version="$VERSION"
    [ "$archive_version" = "latest" ] && archive_version="$LATEST_GITEE_VERSION"
    url="https://gitee.com/$REPO_SLUG/repository/archive/$archive_version.zip"
  else
    if [ "$VERSION" = "latest" ]; then
      url="https://github.com/$REPO_SLUG/releases/latest/download/git-ai-review-hook.zip"
    else
      url="https://github.com/$REPO_SLUG/releases/download/$VERSION/git-ai-review-hook.zip"
    fi
  fi

  if need_cmd curl; then
    curl -fsSL "$url" -o "$zip_file"
  elif need_cmd wget; then
    wget -q "$url" -O "$zip_file"
  else
    printf '%s\n' "curl or wget is required." >&2
    printf '%s\n' "macOS: brew install curl" >&2
    printf '%s\n' "Linux: install curl or wget with your package manager." >&2
    exit 1
  fi
fi

unzip -q "$zip_file" -d "$tmp_dir/package"

package_root="$tmp_dir/package"
if [ ! -d "$package_root/githooks" ]; then
  nested="$(find "$package_root" -type d -name githooks | head -n 1)"
  [ -n "$nested" ] || fail "Package does not contain githooks/."
  package_root="$(dirname "$nested")"
fi

if [ "$INSTALL_SCOPE" = "global" ]; then
  target="$HOME/.git-ai-review-hook/githooks"
else
  target="$repo_root/githooks"
fi

rm -rf "$target"
mkdir -p "$(dirname "$target")"
cp -R "$package_root/githooks" "$target"

sh "$target/install.sh" "$INSTALL_SCOPE"
