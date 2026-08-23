[English](README.en.md) | 中文

# caddy-fp

一个自带 forward_proxy 插件的 Caddy 镜像，amd64 和 arm64 都有。

官方 Caddy 不带正向代理功能，想加插件就得自己编译。这个仓库让 GitHub Actions 代劳：每次构建都从源码编译，先跑一遍功能测试，通过了才发布到 Docker Hub 和 GHCR。

```
docker pull colinxu/caddy-fp:latest
docker pull ghcr.io/xuzhonglin/caddy-fp:latest
```

## 它能做什么

- HTTP 正向代理：明文请求走绝对 URL，HTTPS 走 CONNECT 隧道（隧道是端到端加密的，代理本身看不到内容）
- 账号密码认证，`hide_ip` / `hide_via` 不给上游留痕迹
- 可以级联 tinyproxy 之类的上游代理
- 非 root 运行，镜像只有 60MB 左右

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

把仓库里的 `Caddyfile` 拷过去，改掉域名和密码，`docker compose up -d` 完事。证书 Caddy 自己搞定。

客户端这样用：

```bash
curl -x https://myuser:myStrongPass@your-domain.com https://httpbin.org/ip
```

返回的 IP 是服务器而不是你本机，就说明通了。浏览器里选 HTTPS 代理（secure web proxy）类型。

配置长这样：

```caddyfile
your-domain.com {
	forward_proxy {
		basic_auth myuser myStrongPass   # 行内两参数，密码明文即可
		hide_ip
		hide_via
		# upstream tinyproxy:8888        # 需要级联时打开
	}
	respond "Hello" 200
}
```

再说一遍，`basic_auth` 别删。公网上的扫描器几小时就能摸到一个无认证代理，到时候它就是别人的免费跳板了。

## 版本自动跟进

仓库里有个 `.caddy-version` 文件，是版本的唯一来源。`watch-caddy-release` 这个 workflow 每天早上跑一次，去查 Caddy 官方仓库的最新 release，发现新版本就自动改版本号、提交代码、触发构建，构建结果它也会盯着，失败会标红提醒你。

也就是说 Caddy 出了新版，你什么都不用做，最多半天后新镜像就躺在你仓库里了。

想手动升级也一样：改 `.caddy-version` 和 `Dockerfile` 里的 `CADDY_VERSION`，推上去，然后到 Actions 页面手动触发 `build-and-push`。

## 本地验证

装好 podman 或 docker 之后：

```bash
bash verify.sh ghcr.io/xuzhonglin/caddy-fp:2.11.4
```

脚本会起一个测试容器，检查插件是否在、无凭据和错误密码是否被 407 拦住、带凭据的明文代理和 HTTPS 隧道是否正常。四项全过才算数。

本地构建（国内网络建议换个 alpine 源）：

```bash
docker build -t caddy-fp:test \
  --build-arg ALPINE_IMAGE=docker.m.daocloud.io/library/alpine:3.20 .
```

## CI 配置

仓库 Secrets 需要两项：`DOCKERHUB_USERNAME` 和 `DOCKERHUB_TOKEN`（在 Docker Hub 的 Security 页面生成，给 Read/Write 权限）。GHCR 用的是 GitHub 自带的 token，不用管。

两个 workflow：

- `build-and-push`：冒烟测试 → 双架构构建 → 推送两个 registry 的 `latest` 和版本号标签
- `watch-caddy-release`：每天检查上游新版本，自动跟进
