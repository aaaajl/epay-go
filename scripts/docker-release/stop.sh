#!/bin/bash
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "错误: 请使用 ./stop.sh 执行"
    return 1 2>/dev/null || exit 1
fi

set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env"
[ -f "$ENV_FILE" ] || ENV_FILE="../.env"

docker compose --env-file "$ENV_FILE" down
echo "服务已停止"
