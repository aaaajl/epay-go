#!/usr/bin/env bash
# 一条命令部署 epay-go。
#
#   ./deploy.sh local    # 构建当前架构镜像，本机以 local 模式启动（公网库）
#   ./deploy.sh prod     # 构建 linux/amd64 → 上传 → docker load → 以 prod 模式重启
#
# local 走 deploy-local.sh；prod 走 deploy-prod.sh（流程对齐 new-api deploy-master.sh）。
# 子脚本的选项原样转发。远端 .env 不会被覆盖。
#
# 用法:
#   ./deploy.sh local
#   ./deploy.sh local --skip-build
#   ./deploy.sh local --no-cache
#   ./deploy.sh local --restart
#   ./deploy.sh local --logs
#   ./deploy.sh local --down
#   ./deploy.sh local --status
#
#   ./deploy.sh prod
#   ./deploy.sh prod --skip-build
#   ./deploy.sh prod --no-restart
#   ./deploy.sh prod --sync-scripts
#   ./deploy.sh prod --status
#   ./deploy.sh prod --no-cache
#
# 环境变量（prod）:
#   REMOTE_HOST / REMOTE_USER / REMOTE_DIR / SSH_KEY / SSH_PORT / IMAGE / ENV_MODE / ARCHIVE
# 环境变量（两边）:
#   IMAGE            默认 epay-go:local

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 <local|prod> [options]

  local    构建当前架构镜像，并在本机以 local 模式启动（公网库 101.132.81.209）
  prod     构建 linux/amd64 镜像，上传到生产机 docker load 后以 prod 模式重启（内网库）

local 选项（转交 deploy-local.sh）:
  --skip-build     跳过镜像构建
  --no-cache       构建时不使用缓存
  --restart        不构建，按上次环境强制重建容器
  --logs           启动后跟随日志
  --down           停止并移除容器
  --status         查看本机容器与健康检查

prod 选项（转交 deploy-prod.sh，对齐 new-api deploy-master.sh）:
  --skip-build     跳过镜像构建，直接使用已有 tar.gz
  --no-restart     只上传并 docker load，不执行远程重启
  --sync-scripts   强制用本地 compose / start.sh 覆盖远端
  --status         仅查看远程服务状态
  --no-cache       构建时不使用缓存

Examples:
  $0 local
  $0 local --logs
  $0 prod
  $0 prod --skip-build
  $0 prod --sync-scripts
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

MODE="$1"
shift

case "${MODE}" in
  -h|--help)
    usage
    exit 0
    ;;
  local)
    exec "${SCRIPT_DIR}/deploy-local.sh" "$@"
    ;;
  prod)
    exec "${SCRIPT_DIR}/deploy-prod.sh" "$@"
    ;;
  *)
    echo "未知环境: ${MODE}（仅支持 local / prod）" >&2
    usage
    exit 1
    ;;
esac
