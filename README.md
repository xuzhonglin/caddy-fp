# caddy-fp

带 [forwardproxy](https://github.com/caddyserver/forwardproxy) 插件的 Caddy 正向代理镜像，支持 `linux/amd64` 与 `linux/arm64` 双架构。

```
docker pull colinxu/caddy-fp:latest
# 或 GitHub Container Registry（国内网络通常更顺畅）
docker pull ghcr.io/xuzhonglin/caddy-fp:latest
```

- Caddy 版本：**v2.11.4**
- 认证：HTTP Basic（`basic_auth myuser myStrongPass`）
- 支持：明文 HTTP 代理（绝对 URL）+ HTTPS CONNECT 隧道 + 可选 tinyproxy 级联
- 非 root 用户运行；`hide_ip` / `hide_via` 隐藏代理痕迹

## 目录结构

```
caddy-fp/
├── dist/
│   ├── caddy-linux-amd64    # xcaddy 交叉编译产物（含插件）
│   └── caddy-linux-arm64
├── Dockerfile               # 按 TARGETARCH 自动选择二进制
├── Caddyfile                # 生产配置示例（443 + 自动 HTTPS）
├── test-Caddyfile           # 本地验证用（8888 明文入口）
├── verify.sh                # 一键功能验证脚本
└── .github/workflows/docker.yml  # CI：冒烟测试 → 双架构构建推送
```

## CI 自动构建（GitHub Actions）

推送 `v*` tag 或手动触发 workflow 即可。需要在仓库 **Settings → Secrets and variables → Actions** 配置：

| Secret | 说明 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub → Account Settings → Security → New Access Token（Read/Write） |

流程：amd64 镜像冒烟测试（407 拦截 + 隧道连通性）→ 通过后 QEMU + buildx 构建双架构并推送。

升级 Caddy 版本三步：

```bash
# 1. 本地重新交叉编译（Go 1.22+，xcaddy）
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 xcaddy build \
  --with github.com/caddyserver/forwardproxy --output dist/caddy-linux-amd64
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 xcaddy build \
  --with github.com/caddyserver/forwardproxy --output dist/caddy-linux-arm64

# 2. 更新 .github/workflows/docker.yml 中 tags 的版本号
# 3. git commit + 打 v* tag 推送触发 CI
```

## 本地验证

```bash
bash verify.sh    # 需要 podman 或 docker；自动跑 407/错误密码/明文代理/HTTPS 隧道四项检查
```

注意：本机开着其他代理软件时，先关掉或确保环境变量 `http_proxy` 等未设置，脚本会自行 unset。

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
