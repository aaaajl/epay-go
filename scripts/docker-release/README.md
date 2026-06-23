# EPay Go 发布包

复用 new-api 的 PostgreSQL / Redis，**单容器**运行。依赖等待与数据库创建在应用启动时由 Go 代码完成。

## 部署

```bash
cp .env.example .env   # 首次部署，编辑配置
./deploy.sh
```

发布目录自带 `.env`；若位于项目内且尚无 `.env`，`deploy.sh` 会从上级目录复制。

## 常用命令

```bash
docker compose ps
docker compose logs -f backend
./stop.sh
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `SHARED_NETWORK` | new-api Docker 网络，如 `wingrid-api_new-api-network` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | 连接共享 postgres |
| `REDIS_PASSWORD` / `REDIS_DB` | 连接共享 redis |
| `HTTP_PORT` | 宿主机端口，默认 `3889` |
