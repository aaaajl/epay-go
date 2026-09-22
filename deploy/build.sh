#!/usr/bin/env bash
# 构建本地 Docker 镜像（当前 CPU 架构，默认 tag: epay-go:local）
#
# 用法：
#   ./build.sh                  # 构建当前架构
#   ./build.sh --no-cache       # 不使用缓存重建
#   IMAGE=epay-go:dev ./build.sh
#
# 构建完成后：./start.sh local

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

IMAGE="${IMAGE:-epay-go:local}"
NO_CACHE=""

for arg in "$@"; do
  case "${arg}" in
    --no-cache) NO_CACHE="--no-cache" ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: ${arg}" >&2
      echo "用法: $0 [--no-cache]" >&2
      exit 1
      ;;
  esac
done

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
  IMAGE="${IMAGE:-epay-go:local}"
fi

BASE_IMAGE_REGISTRY="${DOCKER_REGISTRY_MIRROR:-${BASE_IMAGE_REGISTRY:-docker.m.daocloud.io/library}}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
APK_MIRROR="${APK_MIRROR:-mirrors.aliyun.com}"

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker 命令" >&2
  exit 1
fi

echo "==> 仓库根目录: ${REPO_ROOT}"
echo "==> 构建镜像:   ${IMAGE}（当前架构）"
echo "==> Dockerfile: ${REPO_ROOT}/Dockerfile"

cd "${REPO_ROOT}"
# macOS 自带 bash 3.2 + set -u 下空数组会报 unbound variable
# shellcheck disable=SC2086
docker build ${NO_CACHE} \
  --build-arg "BASE_IMAGE_REGISTRY=${BASE_IMAGE_REGISTRY}" \
  --build-arg "NPM_REGISTRY=${NPM_REGISTRY}" \
  --build-arg "GOPROXY=${GOPROXY}" \
  --build-arg "APK_MIRROR=${APK_MIRROR}" \
  -f Dockerfile \
  -t "${IMAGE}" \
  .

echo ""
echo "==> 构建完成: ${IMAGE}"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' --filter "reference=${IMAGE}"
echo ""
echo "下一步:"
echo "  ${SCRIPT_DIR}/start.sh local"
