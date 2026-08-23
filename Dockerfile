# 多阶段构建：官方 builder 镜像内置 Go + xcaddy，Go 原生交叉编译出目标架构二进制，
# 因此 builder 阶段始终以 amd64 运行，无需 QEMU；仅最终阶段的 apk 需要 arm64 模拟。
# 注意：所有 ARG 必须声明在第一个 FROM 之前（全局作用域），否则后续 FROM 引用会解析为空。

ARG CADDY_VERSION=2.11.4
ARG ALPINE_IMAGE=alpine:3.20

FROM caddy:${CADDY_VERSION}-builder AS builder
ARG TARGETARCH
RUN GOARCH=${TARGETARCH} xcaddy build \
      --with github.com/caddyserver/forwardproxy \
      --output /usr/bin/caddy \
      && /usr/bin/caddy version

FROM ${ALPINE_IMAGE}

RUN apk add --no-cache ca-certificates tzdata

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN chmod +x /usr/bin/caddy && /usr/bin/caddy version

# 非 root 运行更安全
RUN addgroup -S caddy && adduser -S caddy -G caddy
USER caddy

EXPOSE 80 443 443/udp 2019

VOLUME ["/data", "/config"]

ENTRYPOINT ["/usr/bin/caddy"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
