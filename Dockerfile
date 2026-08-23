# builder 阶段固定跑在构建机原生架构上，Go 交叉编译出目标架构二进制
ARG CADDY_VERSION=2.11.4
ARG ALPINE_IMAGE=alpine:3.20

FROM --platform=$BUILDPLATFORM caddy:${CADDY_VERSION}-builder AS builder
ARG TARGETARCH
RUN GOARCH=${TARGETARCH} xcaddy build \
      --with github.com/caddyserver/forwardproxy \
      --output /usr/bin/caddy \
      && /usr/bin/caddy version

FROM ${ALPINE_IMAGE}
RUN apk add --no-cache ca-certificates tzdata

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN chmod +x /usr/bin/caddy && /usr/bin/caddy version

RUN addgroup -S caddy && adduser -S caddy -G caddy
USER caddy

EXPOSE 80 443 443/udp 2019
VOLUME ["/data", "/config"]

ENTRYPOINT ["/usr/bin/caddy"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
