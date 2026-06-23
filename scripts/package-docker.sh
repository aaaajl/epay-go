#!/bin/bash
# 构建 Docker 镜像并打包到 release/ 目录

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SRC="$ROOT/scripts/docker-release"
RELEASE_DIR="$ROOT/release"
IMAGE_NAME="epay-go"
IMAGE_TAG="latest"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"

resolve_version() {
    date +%Y%m%d%H%M%S
}

if [ -f "$ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
fi

VERSION="$(resolve_version)"
ARCHIVE="$ROOT/release-${VERSION}.tar.gz"

BASE_IMAGE_REGISTRY="${DOCKER_REGISTRY_MIRROR:-docker.m.daocloud.io/library}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
APK_MIRROR="${APK_MIRROR:-mirrors.aliyun.com}"
# 服务器多为 x86_64；在 Mac (arm64) 上构建须指定平台，否则目标机会 exec format error
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"

echo "=== 构建 Docker 镜像 ${IMAGE_REF} (${DOCKER_PLATFORM}) ==="
docker build \
    --platform "${DOCKER_PLATFORM}" \
    --build-arg "BASE_IMAGE_REGISTRY=${BASE_IMAGE_REGISTRY}" \
    --build-arg "NPM_REGISTRY=${NPM_REGISTRY}" \
    --build-arg "GOPROXY=${GOPROXY}" \
    --build-arg "APK_MIRROR=${APK_MIRROR}" \
    -t "${IMAGE_REF}" \
    "$ROOT"

echo "=== 准备发布目录 release/ ==="
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "=== 导出镜像 ==="
docker save "${IMAGE_REF}" -o "$RELEASE_DIR/epay-go.tar"

echo "=== 复制部署文件 ==="
cp "$RELEASE_SRC/docker-compose.yml" "$RELEASE_DIR/"
cp "$ROOT/.env.example" "$RELEASE_DIR/"
cp "$RELEASE_SRC/README.md" "$RELEASE_DIR/"
cp "$RELEASE_SRC/deploy.sh" "$RELEASE_DIR/"
cp "$RELEASE_SRC/stop.sh" "$RELEASE_DIR/"
chmod +x "$RELEASE_DIR/deploy.sh" "$RELEASE_DIR/stop.sh"
echo "$VERSION" > "$RELEASE_DIR/VERSION"

TMP_ARCHIVE="$(mktemp)"
echo "=== 生成压缩包 ${ARCHIVE} ==="
tar czf "$TMP_ARCHIVE" -C "$ROOT" release
mv "$TMP_ARCHIVE" "$ARCHIVE"

echo ""
echo "=== 打包完成 ==="
echo "版本:     $VERSION"
echo "部署目录: $RELEASE_DIR"
echo "压缩包:   $ARCHIVE"
