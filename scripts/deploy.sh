#!/bin/bash
# epay-go/scripts/deploy.sh

set -e

echo "=== EPay Go 部署脚本 ==="

# 检查环境变量文件
if [ ! -f .env ]; then
    echo "创建 .env 文件..."
    if [ -f .env.example ]; then
        cp .env.example .env
    else
        echo "请创建 .env 文件并配置必要的环境变量"
        exit 1
    fi
    echo "请编辑 .env 文件配置必要的环境变量"
    exit 1
fi

# 构建镜像
echo "构建 Docker 镜像..."
docker compose build

# 启动服务
echo "启动服务..."
docker compose up -d

# 等待服务就绪
echo "等待服务就绪..."
sleep 10

echo "=== 部署完成 ==="
echo "访问地址: http://localhost:3889"
echo "管理后台: http://localhost:3889/admin/login"
echo "商户中心: http://localhost:3889/merchant/login"
