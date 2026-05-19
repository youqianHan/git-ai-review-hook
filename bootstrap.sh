#!/usr/bin/env sh
set -eu

REPO_SLUG="${AI_REVIEW_HOOK_REPO:-youqianHan/git-ai-review-hook}"
HOST_NAME="${AI_REVIEW_HOOK_HOST:-github}"
VERSION="${AI_REVIEW_HOOK_VERSION:-latest}"
LOCAL_ZIP="${AI_REVIEW_HOOK_ZIP:-}"
INSTALL_SCOPE="${AI_REVIEW_HOOK_SCOPE:-}"
LATEST_GITEE_VERSION="v0.1.6"

fail() {
  printf '%s\n' "ERROR / 错误: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

repo_root=""
if [ -z "$INSTALL_SCOPE" ]; then
  default_scope="global"
  printf '%s [%s]: ' "Install scope / 安装范围 (local global)" "$default_scope" >&2
  IFS= read -r INSTALL_SCOPE || INSTALL_SCOPE=""
  [ -n "$INSTALL_SCOPE" ] || INSTALL_SCOPE="$default_scope"
fi
case "$INSTALL_SCOPE" in
  local|global) ;;
  *) fail "Invalid AI_REVIEW_HOOK_SCOPE / 无效安装范围: $INSTALL_SCOPE. Use local or global / 请使用 local 或 global." ;;
esac
case "$HOST_NAME" in
  github|gitee) ;;
  *) fail "Invalid AI_REVIEW_HOOK_HOST / 无效下载源: $HOST_NAME. Use github or gitee / 请使用 github 或 gitee." ;;
esac
if [ "$INSTALL_SCOPE" = "local" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$repo_root" ]; then
    fail "Local install requires running inside a Git repository. / 当前项目安装需要在 Git 仓库内运行。"
  fi
fi
[ -n "$repo_root" ] && cd "$repo_root"

if ! need_cmd unzip; then
  printf '%s\n' "unzip is required. / 需要安装 unzip。" >&2
  printf '%s\n' "macOS: xcode-select --install  OR  brew install unzip" >&2
  printf '%s\n' "Linux: install unzip with your package manager. / 请用系统包管理器安装 unzip。" >&2
  exit 1
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t ai-review-hook)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
zip_file="$tmp_dir/git-ai-review-hook.zip"

if [ -n "$LOCAL_ZIP" ]; then
  [ -f "$LOCAL_ZIP" ] || fail "Local zip not found / 本地 zip 不存在: $LOCAL_ZIP"
  cp "$LOCAL_ZIP" "$zip_file"
elif [ "$HOST_NAME" = "gitee" ]; then
  clone_version="$VERSION"
  [ "$clone_version" = "latest" ] && clone_version="main"
  clone_url="https://gitee.com/$REPO_SLUG.git"
  git clone --depth 1 --branch "$clone_version" "$clone_url" "$tmp_dir/repo" ||
    fail "Failed to clone from Gitee / 从 Gitee 克隆失败: $clone_url ($clone_version)"
else
  if [ "$VERSION" = "latest" ]; then
    url="https://github.com/$REPO_SLUG/releases/latest/download/git-ai-review-hook.zip"
  else
    url="https://github.com/$REPO_SLUG/releases/download/$VERSION/git-ai-review-hook.zip"
  fi

  if need_cmd curl; then
    curl -fsSL "$url" -o "$zip_file"
  elif need_cmd wget; then
    wget -q "$url" -O "$zip_file"
  else
    printf '%s\n' "curl or wget is required. / 需要安装 curl 或 wget。" >&2
    printf '%s\n' "macOS: brew install curl" >&2
    printf '%s\n' "Linux: install curl or wget with your package manager. / 请用系统包管理器安装 curl 或 wget。" >&2
    exit 1
  fi
fi

if [ "$HOST_NAME" = "gitee" ] && [ -z "$LOCAL_ZIP" ]; then
  package_root="$tmp_dir/repo"
else
  unzip -q "$zip_file" -d "$tmp_dir/package"

  package_root="$tmp_dir/package"
  if [ ! -d "$package_root/githooks" ]; then
    nested="$(find "$package_root" -type d -name githooks | head -n 1)"
    [ -n "$nested" ] || fail "Package does not contain githooks/. / 安装包中未找到 githooks/ 目录。"
    package_root="$(dirname "$nested")"
  fi
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
