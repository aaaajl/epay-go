# EPay Go

一个基于 Go + Gin + PostgreSQL + Redis + Vue 3 的支付系统示例项目，提供管理后台、商户中心、统一下单、通道管理，以及订单 / 退款 / 结算流程。

## 技术栈

- 后端：Go、Gin、GORM、PostgreSQL、Redis
- 前端：Vue 3、Vite、Arco Design
- 部署：Docker Compose（单镜像 embed 模式，前端 + API 同一进程）

## 目录说明

- `cmd/server`：服务启动入口
- `internal`：后端核心业务
- `web`：前端代码
- `docker-compose.yml`：Docker 部署（复用共享基础设施或独立数据库）

## 快速开始

### 1. 准备环境变量

```bash
cp .env.example .env
```

然后按需修改数据库、Redis、JWT、默认管理员和支付渠道配置。

### 2. 启动项目

当前 `docker-compose.yml` 复用 new-api 项目已启动的 PostgreSQL / Redis，不重复拉起数据库服务。

前置条件：

```bash
cd ../new-api && docker compose up -d postgres redis
```

启动 epay-go：

```bash
docker compose up -d --build
```

默认端口：

- `3889`：Web 服务（前端 + API 一体）
- `3890`：同上（备用映射，实际指向同一进程）

### 常用访问入口

部署完成后，可直接访问以下前端路径：

- **管理员登录**：`/admin/login`
- **商户注册**：`/merchant/register`
- **商户登录**：`/merchant/login`

## 环境变量

参考 `.env.example`。常用变量包括：

- `DB_USER` / `POSTGRES_USER`
- `DB_PASSWORD` / `POSTGRES_PASSWORD`
- `DB_NAME`
- `REDIS_PASSWORD`
- `REDIS_DB`
- `SHARED_NETWORK`（复用 new-api 网络时）
- `JWT_SECRET`
- `DEFAULT_ADMIN_USERNAME`
- `DEFAULT_ADMIN_PASSWORD`
- `ALIPAY_APP_ID`
- `ALIPAY_PRIVATE_KEY`
- `ALIPAY_PUBLIC_KEY`
- `WECHAT_APP_ID`
- `WECHAT_MCH_ID`
- `WECHAT_API_KEY`

系统首次启动且数据库中没有管理员时，会使用 `DEFAULT_ADMIN_USERNAME` 和 `DEFAULT_ADMIN_PASSWORD` 初始化默认管理员。

生产环境如需 HTTPS，在宿主机或上游负载均衡（如云厂商 LB、Traefik 等）配置反向代理即可，后端容器直接暴露 `8080`。

## 支付参数说明

支付通道和支付场景是分开的：

- `type` / `pay_type`：决定渠道，例如 `wxpay`、`alipay`
- `pay_method`：决定场景，例如 `native`、`scan`、`h5`、`jsapi`、`web`

### 关键规则

- `type=native` **不允许单独使用**，因为无法判断是微信还是支付宝
- 后端支持显式别名，并会自动归一化：
  - `WX_NATIVE`
  - `WX_JSAPI`
  - `WX_H5`
  - `ALIPAY_SCAN`
  - `ALIPAY_H5`
  - `ALIPAY_WEB`

### 推荐传法

- **微信 Native**
  - `type=WX_NATIVE`
  - 或 `type=wxpay&pay_method=native`

- **微信 JSAPI**
  - `type=WX_JSAPI`
  - 或 `type=wxpay&pay_method=jsapi`

- **支付宝扫码**
  - `type=ALIPAY_SCAN`
  - 或 `type=alipay&pay_method=scan`

- **支付宝 H5**
  - `type=ALIPAY_H5`
  - 或 `type=alipay&pay_method=h5`

- **支付宝网页支付**
  - `type=ALIPAY_WEB`
  - 或 `type=alipay&pay_method=web`

## 构建说明

前端静态资源通过 `go:embed` 嵌入 Go 二进制，与 [new-api](https://github.com/QuantumNous/new-api) 相同模式。

### 本地开发

前后端分离开发（推荐）：

```bash
# 终端 1：后端 API
make dev-backend

# 终端 2：Vite 开发服务器（代理 /api 到后端）
make dev-frontend
```

### 本地构建单二进制

```bash
make build
./epay-server
```

`make build` 会先执行 `npm run build`，将产物复制到 `internal/web/dist`，再以 `-tags embed` 编译。

### Docker 构建

Dockerfile 多阶段构建：Node 构建前端 → 复制到 `internal/web/dist` → Go 编译嵌入。

如果在中国大陆网络环境构建，可以在 `.env` 中设置：

```env
GOPROXY=https://goproxy.cn,direct
```

### 打包 Docker 部署目录

生成可直接拷贝到目标服务器部署的 `release/` 目录（含预构建镜像、与根目录一致的 compose、部署脚本）。发布包复用 new-api 的 PostgreSQL / Redis，不单独拉起数据库。

```bash
make package-docker
```

版本号写入 `release/VERSION`（打包时刻日期时间戳），压缩包为 `release-{version}.tar.gz`。

```bash
tar xzf release-*.tar.gz && cd release && ./deploy.sh
```

（需先启动 new-api 基础设施。）
