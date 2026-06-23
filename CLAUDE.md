# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

EPay-Go 是一个基于 Go 的聚合支付网关系统，支持支付宝和微信支付。系统分为三个主要部分：
- 对外支付 API（供商户调用）
- 商户中心（商户管理订单和结算）
- 管理后台（管理员管理商户和通道）

## 常用命令

### 本地开发

```bash
# 启动开发环境（需要先配置 config.yaml）
go run cmd/server/main.go

# 构建可执行文件
go build -o epay-server cmd/server/main.go

# 运行测试
go test ./...

# 下载依赖
go mod tidy
```

### Docker 部署

```bash
# 单服务 compose，应用启动时自动等待依赖并创建数据库
docker compose up -d --build

# 查看服务日志
docker compose logs -f

# 停止服务
docker compose down

# 重新构建
docker compose build --no-cache
```

当前 `docker-compose.yml` 默认复用 new-api 的 PostgreSQL / Redis，不包含独立数据库容器。

### 访问地址

- Web（前端 + API）: http://localhost:3889（Docker 默认映射）
- 管理后台: http://localhost:3889/admin/login
- 商户中心: http://localhost:3889/merchant/login
- 健康检查: http://localhost:3889/health
- 本地开发（无 embed）: http://localhost:8080 仅 API；前端用 `make dev-frontend`

## 架构设计

### 目录结构

```
cmd/server/          # 主程序入口，负责初始化和启动
internal/
  ├── handler/       # HTTP 请求处理层（按角色分包：admin/merchant/payment）
  ├── service/       # 业务逻辑层
  ├── repository/    # 数据访问层
  ├── model/         # 数据模型（GORM）
  ├── payment/       # 支付适配器（核心架构）
  ├── router/        # 路由配置
  ├── middleware/    # 中间件（JWT、CORS、日志等）
  ├── config/        # 配置管理（Viper）
  ├── database/      # 数据库初始化和迁移
  └── cache/         # Redis 缓存
pkg/                 # 可复用工具包（jwt/response/sign/utils）
web/                 # 前端代码
```

### 分层架构

采用经典三层架构：
- **Handler 层**: 处理 HTTP 请求、参数验证、响应封装
- **Service 层**: 核心业务逻辑、事务管理
- **Repository 层**: 数据库操作、查询封装

示例调用链：`handler/payment/create.go` -> `service/order.go` -> `repository/order.go`

### 支付适配器模式

核心设计在 `internal/payment/` 目录：

1. **统一接口** (`adapter.go`): 定义 `PaymentAdapter` 接口，包含：
   - `CreateOrder`: 创建支付订单
   - `QueryOrder`: 查询订单状态
   - `Refund`: 退款
   - `ParseNotify`: 解析异步回调
   - `NotifySuccess`: 返回回调成功响应

2. **工厂模式** (`factory.go`): 通过 `Register()` 注册适配器，`NewAdapter()` 创建实例

3. **具体实现**:
   - `alipay.go`: 支付宝适配器
   - `wechat.go`: 微信支付适配器

4. **注册机制**: 在 `cmd/server/main.go` 中通过匿名导入 `_ "github.com/example/epay-go/internal/payment"` 触发 `init()` 函数自动注册适配器

**添加新支付通道**:
1. 在 `internal/payment/` 创建新文件（如 `stripe.go`）
2. 实现 `PaymentAdapter` 接口
3. 在 `init()` 函数中调用 `Register("stripe", newStripeAdapter)`
4. 无需修改其他代码，系统自动支持新通道

### JWT 认证

系统使用双 Token 机制（`pkg/jwt/`）:
- `TokenTypeAdmin`: 管理员 Token
- `TokenTypeMerchant`: 商户 Token

中间件 `middleware.JWTAuth(tokenType)` 根据 Token 类型进行权限校验。

### 路由组织

所有路由在 `internal/router/router.go` 中统一注册：
- `/api/pay/*`: 对外支付 API（无需登录）
- `/admin/*`: 管理后台 API（需要管理员 Token）
- `/merchant/*`: 商户中心 API（需要商户 Token）

### 异步通知机制

系统启动时会启动一个后台工作协程 (`service.NotifyService.StartNotifyWorker`)，负责：
- 处理支付成功后的异步通知
- 重试失败的通知
- 通过 Context 支持优雅关闭

### 配置管理

使用 Viper 管理配置，配置文件 `config.yaml`：
- 服务器端口和运行模式
- 数据库连接（PostgreSQL）
- Redis 连接
- JWT 密钥和过期时间

**首次运行**: 复制 `config.example.yaml` 为 `config.yaml` 并修改配置。

### 数据库迁移

程序启动时会自动执行 `database.Migrate()` 进行数据库迁移，无需手动运行 SQL 脚本。

### 核心依赖

- `github.com/gin-gonic/gin`: Web 框架
- `gorm.io/gorm`: ORM
- `github.com/go-pay/gopay`: 支付 SDK（支持支付宝、微信等）
- `github.com/golang-jwt/jwt/v5`: JWT 认证
- `github.com/redis/go-redis/v9`: Redis 客户端
- `github.com/shopspring/decimal`: 金额精确计算

## 开发注意事项

### 金额处理

**必须使用** `github.com/shopspring/decimal` 处理所有金额，避免浮点数精度问题：
```go
amount := decimal.NewFromFloat(100.50)  // 正确
amount := 100.50  // 错误 - 永远不要用 float64 存储金额
```

### 支付回调验证

每个支付适配器的 `ParseNotify()` 必须：
1. 验证签名
2. 验证订单金额
3. 验证订单状态
4. 返回统一的 `NotifyResult` 结构

### 事务管理

涉及资金变动的操作必须在 Service 层使用数据库事务，参考现有 Service 实现。

### 模块导入路径

项目 module 为 `github.com/example/epay-go`，导入内部包时使用完整路径：
```go
import "github.com/example/epay-go/internal/service"
```
