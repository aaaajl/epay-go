# epay-go/Dockerfile
# 阶段1: 构建前端
ARG BASE_IMAGE_REGISTRY=docker.m.daocloud.io/library
FROM ${BASE_IMAGE_REGISTRY}/node:20-alpine AS frontend

WORKDIR /app/web

ARG NPM_REGISTRY=https://registry.npmmirror.com
ENV NODE_ENV=development

COPY web/package*.json ./
RUN sed -i 's|http://mirrors.tencentyun.com/npm/|https://registry.npmmirror.com/|g' package-lock.json \
    && npm config set registry ${NPM_REGISTRY} \
    && npm ci --include=dev

COPY web/ .
RUN npm run build:docker

# 阶段2: 构建 Go 后端（嵌入前端静态资源）
ARG BASE_IMAGE_REGISTRY=docker.m.daocloud.io/library
FROM ${BASE_IMAGE_REGISTRY}/golang:1.25-alpine AS builder

WORKDIR /app

ARG GOPROXY=https://goproxy.cn,direct
ARG APK_MIRROR=mirrors.aliyun.com
ENV GOPROXY=${GOPROXY}

RUN sed -i "s|https://dl-cdn.alpinelinux.org|https://${APK_MIRROR}|g" /etc/apk/repositories \
    && apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=frontend /app/web/dist ./internal/web/dist

ARG TARGETARCH=amd64
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -tags embed -a -installsuffix cgo -o epay-server ./cmd/server

# 阶段3: 运行镜像
ARG BASE_IMAGE_REGISTRY=docker.m.daocloud.io/library
FROM ${BASE_IMAGE_REGISTRY}/alpine:3.19

WORKDIR /app

ARG APK_MIRROR=mirrors.aliyun.com
RUN sed -i "s|https://dl-cdn.alpinelinux.org|https://${APK_MIRROR}|g" /etc/apk/repositories \
    && apk --no-cache add ca-certificates tzdata

ENV TZ=Asia/Shanghai

COPY --from=builder /app/epay-server .
COPY --from=builder /app/config.example.yaml ./config.yaml

EXPOSE 8080

CMD ["./epay-server"]
