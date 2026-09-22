#!/usr/bin/env bash
# 本地一键部署：构建当前架构镜像 → 以 local 模式启动（公网库 101.132.81.209）
# 统一入口: ./deploy.sh local
#
# 用法:
#   ./deploy-local.sh                 # 构建并启动
#   ./deploy-local.sh --skip-build    # 跳过构建，使用已有镜像
#   ./deploy-local.sh --no-cache      # 构建时不使用缓存
#   ./deploy-local.sh --restart       # 不构建，按上次环境强制重建容器
#   ./deploy-local.sh --logs          # 启动后跟随日志
#   ./deploy-local.sh --down          # 停止
#   ./deploy-local.sh --status        # 查看状态
#
# 前置: deploy/.env（不存在时会尝试从仓库根 .env 或 .env.example 生成）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
IMAGE="${IMAGE:-epay-go:local}"

SKIP_BUILD=false
NO_CACHE=""
DO_RESTART=false
DO_DOWN=false
FOLLOW_LOGS=false
STATUS_ONLY=false

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --skip-build     跳过镜像构建
  --no-cache       传给 build.sh，不使用构建缓存
  --restart        不构建，执行 start.sh local --restart
  --logs           启动后跟随日志
  --down           停止并移除容器
  --status         仅查看本机容器与健康检查
  -h, --help       显示帮助

Environment overrides:
  IMAGE            默认 epay-go:local
  DB_HOST_LOCAL    默认 101.132.81.209
  REDIS_HOST_LOCAL 默认共享网络中的 redis

Examples:
  $0
  $0 --skip-build
  $0 --restart
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true; shift ;;
    --no-cache) NO_CACHE="--no-cache"; shift ;;
    --restart) DO_RESTART=true; shift ;;
    --logs) FOLLOW_LOGS=true; shift ;;
    --down) DO_DOWN=true; shift ;;
    --status) STATUS_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

ensure_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    return 0
  fi
  if [[ -f "${REPO_ROOT}/.env" ]]; then
    cp "${REPO_ROOT}/.env" "${ENV_FILE}"
    echo "==> 已从仓库根 .env 复制到 ${ENV_FILE}"
    return 0
  fi
  if [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
    cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"
    echo "已创建 ${ENV_FILE}，请编辑 JWT_SECRET / SHARED_NETWORK 后重新执行"
    exit 1
  fi
  echo "错误: 未找到 .env"
  exit 1
}

show_status() {
  local port
  port="${HTTP_PORT:-3889}"
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
    port="${HTTP_PORT:-3889}"
  fi
  echo "==> 本机状态"
  docker ps --filter name=epay-go --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' || true
  if [[ -f "${SCRIPT_DIR}/docker-compose.yml" && -f "${ENV_FILE}" ]]; then
    docker compose -f "${SCRIPT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" ps || true
  fi
  curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:${port}/health" || true
  echo
}

main() {
  export IMAGE

  if [[ "${STATUS_ONLY}" == "true" ]]; then
    show_status
    exit 0
  fi

  ensure_env_file

  echo "Repo:  ${REPO_ROOT}"
  echo "Image: ${IMAGE}"
  echo "Mode:  local"

  if [[ "${DO_DOWN}" == "true" ]]; then
    "${SCRIPT_DIR}/start.sh" --down
    exit 0
  fi

  if [[ "${DO_RESTART}" == "true" ]]; then
    "${SCRIPT_DIR}/start.sh" local --restart
    exit 0
  fi

  if [[ "${SKIP_BUILD}" != "true" ]]; then
    echo "==> 构建本地镜像"
    # shellcheck disable=SC2086
    "${SCRIPT_DIR}/build.sh" ${NO_CACHE}
  else
    echo "==> 跳过构建"
  fi

  if [[ "${FOLLOW_LOGS}" == "true" ]]; then
    "${SCRIPT_DIR}/start.sh" local --logs
  else
    "${SCRIPT_DIR}/start.sh" local
  fi

  echo "==> 本地部署完成。"
}

main
