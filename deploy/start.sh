#!/usr/bin/env bash
# 启动 epay-go（复用 new-api 的 Redis 网络；数据库按 local / prod 切换）
#
# 用法：
#   ./start.sh local            # 连公网库 101.132.81.209
#   ./start.sh prod             # 连生产内网库 172.16.0.246
#   ./start.sh local --build    # 先构建当前架构镜像再启动
#   ./start.sh prod --logs      # 启动后跟随日志
#   ./start.sh --down           # 停止并移除本 compose 服务
#   ./start.sh --restart        # 沿用上次 local|prod，强制重建容器
#   ./start.sh prod --restart   # 切换库后仅重建 epay-go
#
# 前置：
#   1. cp .env.example .env 并填写 JWT_SECRET / 数据库密码 / SHARED_NETWORK
#   2. 本机镜像先 ./build.sh（或加 --build）；生产机镜像由 deploy-prod.sh docker load
#   3. 首次 up 必须指定 local 或 prod；之后 --restart 会读上次记录

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
MODE_FILE="${SCRIPT_DIR}/.runtime-mode"
DO_BUILD=0
FOLLOW_LOGS=0
ACTION=up
ENV_MODE=""

# local / prod 数据库与 Redis（启动参数覆盖 .env 中的 DB_HOST / REDIS_HOST）
# 与 new-api deploy/master-slave/start-master.sh 的公网 / 内网地址对齐
DB_HOST_LOCAL="${DB_HOST_LOCAL:-101.132.81.209}"
DB_HOST_PROD="${DB_HOST_PROD:-172.16.0.246}"
# 空则稍后用 .env 的 REDIS_HOST，再默认 redis（共享网络中的服务名）
REDIS_HOST_LOCAL="${REDIS_HOST_LOCAL:-}"
REDIS_HOST_PROD="${REDIS_HOST_PROD:-}"

for arg in "$@"; do
  case "${arg}" in
    local|prod) ENV_MODE="${arg}" ;;
    --build) DO_BUILD=1 ;;
    --logs) FOLLOW_LOGS=1 ;;
    --down) ACTION=down ;;
    --restart) ACTION=restart ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: ${arg}" >&2
      echo "用法: $0 local|prod [--build] [--logs] [--down] [--restart]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "未找到 ${ENV_FILE}"
  echo "请先: cp ${SCRIPT_DIR}/.env.example ${ENV_FILE} 并填写配置"
  exit 1
fi

# 调用方已设置的 IMAGE（如 deploy-prod.sh）优先于 .env
_IMAGE_OVERRIDE="${IMAGE-}"
_DB_HOST_LOCAL="${DB_HOST_LOCAL}"
_DB_HOST_PROD="${DB_HOST_PROD}"
_REDIS_HOST_LOCAL="${REDIS_HOST_LOCAL}"
_REDIS_HOST_PROD="${REDIS_HOST_PROD}"

# shellcheck disable=SC1090
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

if [[ -n "${_IMAGE_OVERRIDE}" ]]; then
  IMAGE="${_IMAGE_OVERRIDE}"
fi
IMAGE="${IMAGE:-epay-go:local}"
HTTP_PORT="${HTTP_PORT:-3889}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-epay}"
DB_USER="${POSTGRES_USER:-${DB_USER:-root}}"
DB_PASSWORD="${POSTGRES_PASSWORD:-${DB_PASSWORD:-}}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_DB="${REDIS_DB:-1}"
SHARED_NETWORK="${SHARED_NETWORK:-new-api_new-api-network}"
DB_HOST_LOCAL="${_DB_HOST_LOCAL}"
DB_HOST_PROD="${_DB_HOST_PROD}"
REDIS_HOST_LOCAL="${_REDIS_HOST_LOCAL:-${REDIS_HOST:-redis}}"
REDIS_HOST_PROD="${_REDIS_HOST_PROD:-${REDIS_HOST:-redis}}"
unset _IMAGE_OVERRIDE _DB_HOST_LOCAL _DB_HOST_PROD _REDIS_HOST_LOCAL _REDIS_HOST_PROD

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "缺少必填变量: ${name}（请写入 ${ENV_FILE}）" >&2
    exit 1
  fi
}

require_var DB_PASSWORD
require_var REDIS_PASSWORD
require_var JWT_SECRET
require_var SHARED_NETWORK

resolve_endpoints() {
  case "${ENV_MODE}" in
    local)
      DB_HOST="${DB_HOST_LOCAL}"
      REDIS_HOST="${REDIS_HOST_LOCAL}"
      ;;
    prod)
      DB_HOST="${DB_HOST_PROD}"
      REDIS_HOST="${REDIS_HOST_PROD}"
      ;;
    *)
      echo "无效环境: ${ENV_MODE}（仅支持 local / prod）" >&2
      exit 1
      ;;
  esac
  export DB_HOST REDIS_HOST
}

save_env_mode() {
  printf '%s\n' "${ENV_MODE}" > "${MODE_FILE}"
}

load_env_mode() {
  local require="${1:-1}"
  if [[ -n "${ENV_MODE}" ]]; then
    return 0
  fi
  if [[ -f "${MODE_FILE}" ]]; then
    ENV_MODE="$(tr -d '[:space:]' < "${MODE_FILE}")"
  fi
  if [[ "${ENV_MODE}" != "local" && "${ENV_MODE}" != "prod" ]]; then
    if [[ "${require}" == "1" ]]; then
      echo "未找到上次启动的环境记录，请指定 local 或 prod" >&2
      echo "用法: $0 local|prod --restart" >&2
      exit 1
    fi
    ENV_MODE=local
  fi
}

network_has_redis() {
  local net="$1"
  local names
  names="$(docker network inspect "${net}" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)"
  [[ " ${names} " == *" redis "* || " ${names} " == *" new-api-redis "* ]]
}

ensure_shared_network() {
  # 网络存在还不够：redis 的 DNS 名只在它所在的网络里能解析。
  # 本机 postgres 常在 new-api_new-api-network，而 master-slave 的 redis 在另一张网。
  if docker network inspect "${SHARED_NETWORK}" >/dev/null 2>&1 && network_has_redis "${SHARED_NETWORK}"; then
    return 0
  fi
  local detected="" container net reason="不存在"
  if docker network inspect "${SHARED_NETWORK}" >/dev/null 2>&1; then
    reason="上没有 redis"
  fi
  for container in redis new-api-redis; do
    if docker inspect "${container}" >/dev/null 2>&1; then
      net="$(docker inspect "${container}" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')"
      if [[ -n "${net}" ]] && docker network inspect "${net}" >/dev/null 2>&1; then
        detected="${net}"
        break
      fi
    fi
  done
  if [[ -n "${detected}" ]]; then
    echo "提示: SHARED_NETWORK=${SHARED_NETWORK} ${reason}，改用 ${detected}" >&2
    echo "请写入 .env: SHARED_NETWORK=${detected}" >&2
    SHARED_NETWORK="${detected}"
    export SHARED_NETWORK
    return 0
  fi
  echo "错误: 共享网络 ${SHARED_NETWORK} ${reason}，且未找到 redis / new-api-redis。" >&2
  echo "请先启动 new-api 的 redis，或在 .env 设置 SHARED_NETWORK 为 redis 所在网络。" >&2
  docker network ls >&2 || true
  exit 1
}

compose() {
  mkdir -p "${SCRIPT_DIR}/logs"
  # .env 里的 DB_HOST / REDIS_HOST 会经 compose env_file 注入容器。
  # 用临时 override 把 local|prod 解析后的值写成字面量，确保覆盖 .env。
  local override rc
  override="$(mktemp)"
  # 端口写成字面量。--env-file 的 HTTP_PORT 会盖过 shell 插值，local 的 3100 否则不会生效。
  cat > "${override}" <<EOF
services:
  backend:
    environment:
      DB_HOST: "${DB_HOST}"
      REDIS_HOST: "${REDIS_HOST}"
    ports: !override
      - "${HTTP_PORT}:8080"
EOF
  set +e
  DB_HOST="${DB_HOST}" REDIS_HOST="${REDIS_HOST}" SHARED_NETWORK="${SHARED_NETWORK}" \
    docker compose -f "${COMPOSE_FILE}" -f "${override}" --env-file "${ENV_FILE}" "$@"
  rc=$?
  set -e
  rm -f "${override}"
  return "${rc}"
}

assert_host_port_free() {
  local holders name
  holders="$(docker ps --filter "publish=${HTTP_PORT}" --format '{{.Names}}' 2>/dev/null || true)"
  if [[ -z "${holders}" ]]; then
    return 0
  fi
  for name in ${holders}; do
    if [[ "${name}" == "epay-go" ]]; then
      continue
    fi
    echo "端口 ${HTTP_PORT} 已被容器「${name}」占用，无法启动 epay-go。" >&2
    echo "请先释放端口，例如：docker stop ${name}" >&2
    exit 1
  done
}

export IMAGE HTTP_PORT DB_PORT DB_NAME DB_USER DB_PASSWORD
export REDIS_PORT REDIS_DB REDIS_PASSWORD JWT_SECRET SHARED_NETWORK
export DEFAULT_ADMIN_USERNAME DEFAULT_ADMIN_PASSWORD

cd "${SCRIPT_DIR}"

case "${ACTION}" in
  down)
    echo "==> 停止 epay-go"
    load_env_mode 0
    resolve_endpoints
    ensure_shared_network
    compose down
    exit 0
    ;;
  restart)
    load_env_mode 1
    resolve_endpoints
    save_env_mode
    ensure_shared_network
    echo "==> 重启 epay-go"
    echo "    ENV=${ENV_MODE}"
    echo "    DB_HOST=${DB_HOST}  REDIS_HOST=${REDIS_HOST}"
    echo "    IMAGE=${IMAGE}"
    assert_host_port_free
    compose up -d --force-recreate --no-deps backend
    compose ps
    exit 0
    ;;
esac

if [[ -z "${ENV_MODE}" ]]; then
  echo "请指定环境: local 或 prod" >&2
  echo "用法: $0 local|prod [--build] [--logs]" >&2
  exit 1
fi

resolve_endpoints
save_env_mode

if [[ "${DO_BUILD}" -eq 1 ]]; then
  echo "==> 构建镜像"
  if [[ "${ENV_MODE}" == "prod" ]]; then
    "${SCRIPT_DIR}/buildProd.sh"
  else
    "${SCRIPT_DIR}/build.sh"
  fi
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "镜像不存在: ${IMAGE}"
  if [[ "${ENV_MODE}" == "prod" ]]; then
    echo "请先执行: ${SCRIPT_DIR}/buildProd.sh    或  ${SCRIPT_DIR}/deploy-prod.sh"
  else
    echo "请先执行: ${SCRIPT_DIR}/build.sh    或  ${SCRIPT_DIR}/deploy-local.sh"
  fi
  exit 1
fi

ensure_shared_network
assert_host_port_free

echo "==> 启动 epay-go"
echo "    ENV=${ENV_MODE}"
echo "    DB_HOST=${DB_HOST}:${DB_PORT}  DB_NAME=${DB_NAME}  DB_USER=${DB_USER}"
echo "    REDIS_HOST=${REDIS_HOST}:${REDIS_PORT}  REDIS_DB=${REDIS_DB}"
echo "    IMAGE=${IMAGE}"
echo "    SHARED_NETWORK=${SHARED_NETWORK}"
echo "    端口 ${HTTP_PORT} -> 8080"
compose up -d

echo ""
echo "==> 等待健康检查（首次启动含建库与迁移，可能需要一两分钟）..."
READY=0
for i in $(seq 1 90); do
  if curl -fsS --connect-timeout 2 --max-time 5 \
    "http://127.0.0.1:${HTTP_PORT}/health" >/dev/null 2>&1; then
    echo ""
    echo "==> 服务就绪: http://127.0.0.1:${HTTP_PORT}/health"
    curl -sS "http://127.0.0.1:${HTTP_PORT}/health" || true
    echo ""
    echo "    管理后台: http://127.0.0.1:${HTTP_PORT}/admin/login"
    echo "    商户中心: http://127.0.0.1:${HTTP_PORT}/merchant/login"
    READY=1
    break
  fi
  if [[ $((i % 5)) -eq 0 ]]; then
    echo "    ...仍在等待 (${i}/90，已约 $((i * 2))s)"
  fi
  sleep 2
done
if [[ "${READY}" -ne 1 ]]; then
  echo "健康检查超时，请查看日志:" >&2
  echo "  docker compose -f ${COMPOSE_FILE} logs --tail=100" >&2
  compose ps
  exit 1
fi

compose ps

if [[ "${FOLLOW_LOGS}" -eq 1 ]]; then
  compose logs -f --tail=100
fi
