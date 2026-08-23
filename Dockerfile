# 多架构 Caddy 镜像（携带 forwardproxy 插件）
# 二进制由本地 xcaddy 交叉编译好，放在 dist/ 目录。
# 使用 docker buildx 构建时，TARGETARCH 会自动注入（amd64 / arm64）。

# ALPINE_IMAGE: 国内网络可换镜像源，如 docker.m.daocloud.io/library/alpine:3.20
ARG ALPINE_IMAGE=alpine:3.20
FROM ${ALPINE_IMAGE}

ARG TARGETARCH

# ca-certificates: 代理访问 HTTPS 上游必需
# tzdata: 可选，日志时间用本地时区
RUN apk add --no-cache ca-certificates tzdata

COPY dist/caddy-linux-${TARGETARCH} /usr/bin/caddy
RUN chmod +x /usr/bin/caddy && /usr/bin/caddy version

# 非 root 运行更安全；80/443 >1024 端口在容器内无所谓
RUN addgroup -S caddy && adduser -S caddy -G caddy
USER caddy

EXPOSE 80 443 443/udp 2019

VOLUME ["/data", "/config"]

ENTRYPOINT ["/usr/bin/caddy"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
