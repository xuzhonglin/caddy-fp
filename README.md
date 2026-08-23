[English](README.en.md) | 中文

# caddy-fp

内置 forward_proxy 插件的 Caddy 镜像，提供 linux/amd64 与 linux/arm64 双架构版本。

Caddy 官方版本不包含正向代理功能，启用插件需自行编译。本仓库通过 GitHub Actions 完成源码编译：每次构建均先执行功能冒烟测试，测试通过后方发布至 Docker Hub 与 GHCR。

```
docker pull colinxu/caddy-fp:latest
docker pull ghcr.io/xuzhonglin/caddy-fp:latest
```

## 功能特性

- 支持 HTTP 正向代理：明文请求使用绝对 URL 转发，HTTPS 流量通过 CONNECT 隧道传输。隧道为端到端加密，代理无法查看内容
- 支持用户名密码认证；`hide_ip` 与 `hide_via` 选项可避免向上游泄露客户端信息
- 支持级联 tinyproxy 等上游代理
- 容器以非 root 用户运行，镜像体积约 60MB

## 部署

```yaml
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

将仓库中的 `Caddyfile` 复制至部署目录，修改域名与认证信息后执行 `docker compose up -d`。TLS 证书由 Caddy 自动申请并续期。

客户端使用示例：

```bash
curl -x https://myuser:myStrongPass@your-domain.com https://httpbin.org/ip
```

返回结果中的 IP 为服务器出口地址而非本机地址时，说明代理链路工作正常。浏览器场景下代理类型应选择 HTTPS（secure web proxy）。

完整配置示例：

```caddyfile
your-domain.com {
	forward_proxy {
		basic_auth myuser myStrongPass   # 行内两个参数，密码为明文
		hide_ip
		hide_via
		# upstream tinyproxy:8888        # 需要级联上游时取消注释
	}
	respond "Hello" 200
}
```

注意：`basic_auth` 必须保留。公网上未认证的代理会在数小时内被扫描工具发现并滥用。
