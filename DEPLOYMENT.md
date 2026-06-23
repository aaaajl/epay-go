# EPay Go 部署指南

## 环境要求

- Docker 20.10+
- Docker Compose 2.0+
- 2GB+ 内存
- 10GB+ 磁盘空间

## 架构说明

项目采用 **单镜像 embed 模式**：Vue 前端在构建时嵌入 Go 二进制，由 Gin 同时提供 API 和静态页面，无需单独的 Nginx / Caddy 前端容器。

## 快速开始

### 1. 克隆项目

```bash
git clone <repository-url>
cd epay-go
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件，配置必要的环境变量
```

### 3. 启动服务

当前默认 `docker-compose.yml` 复用 new-api 的 PostgreSQL / Redis：

```bash
# 先启动共享基础设施（在 new-api 目录）
cd ../new-api && docker compose up -d postgres redis

# 启动 epay-go
cd ../epay-go
docker compose up -d --build
```

### 4. 访问服务

- Web 服务: http://localhost:3889
- 管理后台: http://localhost:3889/admin/login
- 商户中心: http://localhost:3889/merchant/login
- 健康检查: http://localhost:3889/health

## 常用命令

```bash
# 查看日志
docker compose logs -f

# 查看服务状态
docker compose ps

# 停止服务
docker compose down

# 重新构建
docker compose build --no-cache

# 进入容器
docker compose exec backend sh
```

## 数据备份

若使用独立 PostgreSQL 容器，备份命令示例：

```bash
docker compose exec postgres pg_dump -U epay epay > backup.sql
cat backup.sql | docker compose exec -T postgres psql -U epay epay
```

复用 new-api 的 PostgreSQL 时，在 new-api 侧执行备份即可。

## 更新部署

```bash
git pull
docker compose build
docker compose up -d
```

## 生产环境 HTTPS

后端容器监听 `8080`，对外映射为宿主机端口（如 `3889`）。生产环境建议在宿主机或云负载均衡上配置反向代理与 TLS，将流量转发到该端口，无需在项目内维护 Nginx / Caddy 配置。

## 故障排查

### 后端无法连接数据库

检查共享 PostgreSQL 是否就绪，以及 `SHARED_NETWORK` 是否与 new-api 实际网络名一致：

```bash
docker network ls | grep new-api
docker compose logs backend
```

### 前端页面无法访问

检查 backend 容器健康状态与 embed 构建是否成功：

```bash
docker compose ps
docker compose logs backend
curl -s http://localhost:3889/health
```

### API 返回 404

确认请求路径以 `/api`、`/admin`、`/merchant` 等后端路由开头；静态资源由同一进程提供，无需额外代理配置。
