# caddy-fp

带 [forwardproxy](https://github.com/caddyserver/forwardproxy) 插件的 Caddy 正向代理镜像，CI 内从源码原生编译，支持 `linux/amd64` 与 `linux/arm64` 双架构。

```
docker pull colinxu/caddy-fp:latest
# 或 GitHub Container Registry（国内网络通常更顺畅）
docker pull ghcr.io/xuzhonglin/caddy-fp:latest
```

- Caddy 版本：**v2.11.4**（见 `Dockerfile` 的 `CADDY_VERSION` 参数）
- 认证：HTTP Basic（`basic_auth myuser myStrongPass`）
- 支持：明文 HTTP 代理（绝对 URL）+ HTTPS CONNECT 隧道 + 可选 tinyproxy 级联
- 非 root 用户运行；`hide_ip` / `hide_via` 隐藏代理痕迹

## 目录结构

```
caddy-fp/
├── Dockerfile               # 多阶段构建：builder 内 xcaddy 编译 + alpine 运行时
├── Caddyfile                # 生产配置示例（443 + 自动 HTTPS）
├── test-Caddyfile           # CI 冒烟测试用（8888 明文入口）
├── verify.sh                # 本地一键功能验证脚本
└── .github/workflows/docker.yml  # CI：冒烟测试 → 双架构构建 → 推送 DH + GHCR
```

## 构建原理

1. **builder 阶段**：基于官方 `caddy:2.11.4-builder`（内置 Go + xcaddy），通过 `GOARCH=$TARGETARCH`
   让 Go 原生交叉编译出目标架构二进制——**全程无需 QEMU 模拟**，速度快且稳定；
2. **运行时阶段**：alpine 底座安装证书/时区数据，拷入静态编译的 Caddy 二进制。
   （arm64 下这一步的 `apk` 由 QEMU 模拟执行，仅几秒钟）

## CI 自动构建（GitHub Actions）

推送 `v*` tag 或在 Actions 页面手动触发。需要配置仓库 Secrets：

| Secret | 说明 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub → Account Settings → Security → New Access Token（Read/Write） |

GHCR 使用 GitHub 内置 `GITHUB_TOKEN`，零配置。产物：

```
colinxu/caddy-fp:latest / :2.11.4
ghcr.io/xuzhonglin/caddy-fp:latest / :2.11.4
```

流程：amd64 镜像冒烟测试（407 拦截 + 隧道连通性）→ 通过后 QEMU + buildx 构建双架构并双推送。

## 升级 Caddy 版本

```bash
# 1. 改 Dockerfile 第一行 ARG CADDY_VERSION=x.y.z
# 2. 改 .github/workflows/docker.yml 中 tags 的版本号
# 3. git commit 后打 v* tag 推送触发 CI
```

## 本地验证

```bash
bash verify.sh    # 需要 podman 或 docker；自动跑 407/错误密码/明文代理/HTTPS 隧道四项检查
```

本地构建镜像（amd64，国内网络建议加 ALPINE_IMAGE 参数）：

```bash
docker build -t caddy-fp:test \
  --build-arg ALPINE_IMAGE=docker.m.daocloud.io/library/alpine:3.20 .
```

注意：本机开着其他代理软件时先关掉或 unset 环境代理变量，脚本会自行处理。

## 服务端部署

```yaml
# docker-compose.yml
services:
  caddy:
    image: colinxu/caddy-fp:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config

volumes:
  caddy_data:
  caddy_config:
```

编辑 `Caddyfile`：改域名和 `basic_auth` 的账号密码，然后 `docker compose up -d`。
Caddy 自动申请续期 Let's Encrypt 证书；如需级联 tinyproxy，取消 `upstream tinyproxy:8888` 注释。

## 客户端使用

```bash
curl -x https://myuser:myStrongPass@your-domain.com https://httpbin.org/ip
# 返回服务器 IP 即链路正常（浏览器选 secure web proxy / HTTPS 代理类型）
```

## forward_proxy 配置速查（该插件的真实语法）

```caddyfile
forward_proxy {
	basic_auth <user> <明文密码>   # 行内两参数，非块、不用 bcrypt
	hide_ip                        # 不向上游暴露客户端 IP
	hide_via                       # 去掉 Via 头
	upstream <host:port>           # 可选：级联上游代理（如 tinyproxy）
	acl { allow <ip/cidr> }        # 可选：访问控制
}
```

## 安全提醒

公网部署**必须配置 `basic_auth`**，否则就是开放代理，几小时内必被扫描滥用。建议同时用 `acl` 限制来源 IP。
