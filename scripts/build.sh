#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_dir="$(dirname -- "$script_dir")"
platform=linux/amd64
version=latest
image_name=z-tailscale-derp
image_tag=latest
output_dir="$repo_dir/dist"

usage() {
  printf '%s\n' \
    '用法：bash scripts/build.sh [选项]' \
    '' \
    '构建可通过 docker load 导入的 DERP 镜像，不推送镜像。' \
    '' \
    '  --platform <平台>           linux/amd64（默认）或 linux/arm64' \
    '  --tailscale-version <版本>  默认解析官方最新稳定版，也接受 v 前缀' \
    '  --image-name <名称>         默认 z-tailscale-derp' \
    '  --image-tag <标签>          默认 latest，同时保留版本标签' \
    '  --output-dir <目录>         默认仓库下的 dist/' \
    '  -h, --help                  查看帮助'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --platform|--tailscale-version|--image-name|--image-tag|--output-dir)
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
        printf '选项 %s 缺少参数。\n' "$1" >&2
        exit 1
      fi
      case "$1" in
        --platform) platform="$2" ;;
        --tailscale-version) version="$2" ;;
        --image-name) image_name="$2" ;;
        --image-tag) image_tag="$2" ;;
        --output-dir) output_dir="$2" ;;
      esac
      shift 2
      ;;
    *) printf '未知选项：%s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$platform" in
  linux/amd64|linux/arm64) ;;
  *) printf '不支持的平台：%s\n' "$platform" >&2; exit 1 ;;
esac

metadata="$(bash "$script_dir/resolve-version.sh" "$version")"
while IFS='=' read -r key value; do
  case "$key" in
    tailscale_version) version="$value" ;;
    tailscale_revision) revision="$value" ;;
    go_version) go_version="$value" ;;
  esac
done <<< "$metadata"

docker buildx version >/dev/null
mkdir -p "$output_dir"
archive="$output_dir/${image_name##*/}_${version}_${platform//\//-}.tar"
if [ -e "$archive" ]; then
  printf '产物已存在，请选择其他输出目录：%s\n' "$archive" >&2
  exit 1
fi

builder="z-tailscale-derp-$(date +%s)-$$"
cleanup() {
  docker buildx rm --force "$builder" >/dev/null 2>&1 || true
}
# 不切换当前默认 builder，仅清理本次创建的临时 builder。
docker buildx create --driver docker-container --name "$builder" >/dev/null
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Tailscale: %s\n源码提交: %s\nGo: %s\n平台: %s\n' \
  "$version" "$revision" "$go_version" "$platform"

docker buildx build \
  --builder "$builder" \
  --platform "$platform" \
  --build-arg "TAILSCALE_VERSION=$version" \
  --build-arg "TAILSCALE_REVISION=$revision" \
  --build-arg "GO_VERSION=$go_version" \
  --build-arg "BUILD_REVISION=$(git -C "$repo_dir" rev-parse HEAD)" \
  --tag "$image_name:$image_tag" \
  --tag "$image_name:$version" \
  --output "type=docker,dest=$archive" \
  "$repo_dir"

printf '\n构建完成：%s\n导入命令：docker load -i "%s"\n' "$archive" "$archive"
