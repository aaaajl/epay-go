#!/usr/bin/env bash
# 构建可在生产机直接运行的 Docker 镜像（linux/amd64）
#
# 用法（在 Mac / 任意架构本机构建，产物部署到 x86_64）：
#   ./buildProd.sh                    # 构建 linux/amd64，加载到本地 Docker
#   ./buildProd.sh --no-cache         # 不使用缓存重建
#   ./buildProd.sh --save             # 构建后导出 tar.gz，供 deploy-prod.sh / scp
#   IMAGE=epay-go:v1 ./buildProd.sh --save
#
# 生产机加载示例：
#   gunzip -c epay-go-local-linux-amd64.tar.gz | docker load
#   ./start.sh prod --restart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

_IMAGE_OVERRIDE="${IMAGE-}"
IMAGE="${IMAGE:-epay-go:local}"
PLATFORM="${PLATFORM:-linux/amd64}"
BUILDER_NAME="${BUILDER_NAME:-epay-amd64}"
NO_CACHE=""
DO_SAVE=0
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}}"

for arg in "$@"; do
  case "${arg}" in
    --no-cache) NO_CACHE="--no-cache" ;;
    --save) DO_SAVE=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: ${arg}" >&2
      echo "用法: $0 [--no-cache] [--save]" >&2
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
fi
if [[ -n "${_IMAGE_OVERRIDE}" ]]; then
  IMAGE="${_IMAGE_OVERRIDE}"
fi
IMAGE="${IMAGE:-epay-go:local}"
unset _IMAGE_OVERRIDE

BASE_IMAGE_REGISTRY="${DOCKER_REGISTRY_MIRROR:-${BASE_IMAGE_REGISTRY:-docker.m.daocloud.io/library}}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
APK_MIRROR="${APK_MIRROR:-mirrors.aliyun.com}"

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker 命令" >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "当前 Docker 不支持 buildx，请升级 Docker Desktop" >&2
  exit 1
fi

ensure_builder() {
  if docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
    docker buildx use "${BUILDER_NAME}" >/dev/null
    return 0
  fi
  echo "==> 创建 buildx builder: ${BUILDER_NAME}"
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container --use >/dev/null
  docker buildx inspect --bootstrap >/dev/null
}

image_safe_name() {
  # epay-go:local → epay-go-local
  echo "${IMAGE}" | tr ':/' '--' | tr -s '-' | sed 's/-$//'
}

echo "==> 仓库根目录: ${REPO_ROOT}"
echo "==> 目标平台:   ${PLATFORM}"
echo "==> 构建镜像:   ${IMAGE}"
echo "==> Dockerfile: ${REPO_ROOT}/Dockerfile"

ensure_builder

cd "${REPO_ROOT}"

# shellcheck disable=SC2086
docker buildx build \
  --platform "${PLATFORM}" \
  ${NO_CACHE} \
  --build-arg "BASE_IMAGE_REGISTRY=${BASE_IMAGE_REGISTRY}" \
  --build-arg "NPM_REGISTRY=${NPM_REGISTRY}" \
  --build-arg "GOPROXY=${GOPROXY}" \
  --build-arg "APK_MIRROR=${APK_MIRROR}" \
  -f Dockerfile \
  -t "${IMAGE}" \
  --load \
  .

echo ""
echo "==> 构建完成: ${IMAGE} (${PLATFORM})"
docker image inspect "${IMAGE}" --format 'ID={{.Id}} Arch={{.Architecture}} OS={{.Os}} Size={{.Size}}'
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' --filter "reference=${IMAGE}"

if [[ "${DO_SAVE}" -eq 1 ]]; then
  mkdir -p "${OUTPUT_DIR}"
  SAFE_NAME="$(image_safe_name)"
  ARCHIVE="${OUTPUT_DIR}/${SAFE_NAME}-linux-amd64.tar.gz"
  echo ""
  echo "==> 导出镜像: ${ARCHIVE}"
  docker save "${IMAGE}" | gzip > "${ARCHIVE}"
  ls -lh "${ARCHIVE}"
  echo ""
  echo "下一步:"
  echo "  ${SCRIPT_DIR}/deploy-prod.sh --skip-build"
fi
