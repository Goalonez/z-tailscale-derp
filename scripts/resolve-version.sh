#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [ "$#" -gt 1 ]; then
  printf '用法：bash scripts/resolve-version.sh [Tailscale版本]\n' >&2
  exit 1
fi

if [ -z "$version" ] || [ "$version" = latest ]; then
  release_url="$(curl -fsSL --connect-timeout 10 --max-time 60 --retry 3 \
    -o /dev/null -w '%{url_effective}' \
    https://github.com/tailscale/tailscale/releases/latest)"
  version="${release_url##*/}"
fi
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.([0-9]+)\.[0-9]+$ ]] || \
   (( 10#${BASH_REMATCH[1]} % 2 != 0 )); then
  printf '请指定稳定版版本号，例如 1.104.6，不支持开发版或任意 Git 引用。\n' >&2
  exit 1
fi

# 同时兼容轻量标签和带注释标签，优先使用解引用后的提交。
refs="$(git ls-remote --exit-code --tags https://github.com/tailscale/tailscale.git \
  "refs/tags/v${version}" "refs/tags/v${version}^{}")"
revision="$(printf '%s\n' "$refs" | awk '
  $2 ~ /\^\{\}$/ { peeled = $1 }
  $2 !~ /\^\{\}$/ { direct = $1 }
  END { print (peeled != "" ? peeled : direct) }
')"
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  printf '无法解析 Tailscale v%s 的源码提交。\n' "$version" >&2
  exit 1
fi

# 从已锁定的提交读取工具链版本，避免解析和构建之间发生版本漂移。
go_mod="$(curl -fsSL --connect-timeout 10 --max-time 60 --retry 3 \
  "https://raw.githubusercontent.com/tailscale/tailscale/${revision}/go.mod")"
go_version="$(printf '%s\n' "$go_mod" | awk '$1 == "go" { print $2; exit }')"
if [[ ! "$go_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  printf '无法从 Tailscale v%s 的 go.mod 解析 Go 版本。\n' "$version" >&2
  exit 1
fi

printf 'tailscale_version=%s\ntailscale_revision=%s\ngo_version=%s\n' \
  "$version" "$revision" "$go_version"
