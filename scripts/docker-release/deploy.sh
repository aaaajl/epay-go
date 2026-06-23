#!/bin/bash
# 部署 epay-go 发布包（./deploy.sh，勿使用 source）

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "错误: 请使用 ./deploy.sh 执行"
    return 1 2>/dev/null || exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LOG_FILE="$SCRIPT_DIR/deploy.log"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "用法: ./deploy.sh [--foreground|-f]"
}

detect_shared_network() {
    local container net
    for container in postgres new-api-postgres new-api; do
        if docker inspect "$container" >/dev/null 2>&1; then
            net=$(docker inspect "$container" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
            [ -n "$net" ] && docker network inspect "$net" >/dev/null 2>&1 && echo "$net" && return 0
        fi
    done
    net=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -i new-api | head -1)
    [ -n "$net" ] && echo "$net" && return 0
    return 1
}

ensure_env_file() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        echo "$SCRIPT_DIR/.env"
        return 0
    fi
    if [ -f "$PROJECT_ROOT/.env" ]; then
        cp "$PROJECT_ROOT/.env" "$SCRIPT_DIR/.env"
        echo "$SCRIPT_DIR/.env"
        return 0
    fi
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        echo "已从 .env.example 创建 $SCRIPT_DIR/.env，请编辑后重新执行"
        exit 1
    fi
    echo "错误: 未找到 .env 文件"
    exit 1
}

ensure_shared_network() {
    local configured="${1:-}"
    local detected
    [ -n "$configured" ] && docker network inspect "$configured" >/dev/null 2>&1 && echo "$configured" && return 0
    detected=$(detect_shared_network) && echo "$detected" && return 0
    return 1
}

compose() {
    docker compose --env-file "$ENV_FILE" "$@"
}

run_deploy() {
    [ -f "$SCRIPT_DIR/epay-go.tar" ] && ! docker image inspect epay-go:latest >/dev/null 2>&1 && \
        docker load -i "$SCRIPT_DIR/epay-go.tar"

    echo "[$(date '+%F %T')] 启动服务..."
    SHARED_NETWORK="$SHARED_NETWORK" compose up -d --remove-orphans
    compose ps
}

FOREGROUND=true
case "${1:-}" in
    --foreground|-f) FOREGROUND=true ;;
    -h|--help) usage; exit 0 ;;
    "") [ -n "${SSH_CONNECTION:-}" ] && FOREGROUND=false ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
esac

echo "=== EPay Go 部署 ==="

ENV_FILE=$(ensure_env_file)
echo "环境变量: $ENV_FILE"

CONFIGURED_NETWORK=$(grep -E '^SHARED_NETWORK=' "$ENV_FILE" | cut -d= -f2- | tr -d "\"'" | xargs || true)
SHARED_NETWORK=$(ensure_shared_network "${CONFIGURED_NETWORK:-wingrid-api_new-api-network}") || {
    echo "错误: 共享网络不存在，请设置 SHARED_NETWORK 或先启动 new-api postgres/redis"
    docker network ls
    exit 1
}

[ "$SHARED_NETWORK" != "$CONFIGURED_NETWORK" ] && \
    echo "提示: 建议在 .env 中设置 SHARED_NETWORK=$SHARED_NETWORK"

if [ "$FOREGROUND" = true ]; then
    run_deploy
    echo "完成: http://localhost:${HTTP_PORT:-3889}"
    exit 0
fi

echo "SSH 后台部署，日志: $LOG_FILE"
: > "$LOG_FILE"
nohup env SCRIPT_DIR="$SCRIPT_DIR" ENV_FILE="$ENV_FILE" SHARED_NETWORK="$SHARED_NETWORK" bash -c '
    set -euo pipefail
    cd "$SCRIPT_DIR"
    [ -f epay-go.tar ] && ! docker image inspect epay-go:latest >/dev/null 2>&1 && docker load -i epay-go.tar
    SHARED_NETWORK="$SHARED_NETWORK" docker compose --env-file "$ENV_FILE" up -d --remove-orphans
    docker compose --env-file "$ENV_FILE" ps
    echo "=== 部署完成 ==="
' >>"$LOG_FILE" 2>&1 &

echo "PID $! — tail -f $LOG_FILE"
