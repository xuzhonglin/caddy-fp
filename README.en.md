[中文](README.md) | English

# caddy-fp

A Caddy image with the forward_proxy plugin built in, for amd64 and arm64.

Stock Caddy has no forward proxy support, and adding a plugin means compiling it yourself. This repo offloads that to GitHub Actions: every build compiles from source, runs a functional smoke test, and only publishes to Docker Hub and GHCR if it passes.

```
docker pull colinxu/caddy-fp:latest
docker pull ghcr.io/xuzhonglin/caddy-fp:latest
```

## What it does

- HTTP forward proxy: plain requests use absolute URLs, HTTPS goes through CONNECT tunnels (end-to-end encrypted — the proxy itself can't see the content)
- Username/password auth, with `hide_ip` / `hide_via` so nothing leaks upstream
- Can chain through an upstream proxy like tinyproxy
- Runs as non-root, image is around 60MB

## Deploy

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

Copy the `Caddyfile` from this repo, change the domain and password, then `docker compose up -d`. Certificates are handled automatically.

Client side:

```bash
curl -x https://myuser:myStrongPass@your-domain.com https://httpbin.org/ip
```

If the returned IP is your server's instead of your own, you're done. In browsers, pick the HTTPS (secure web proxy) type.

The config looks like this:

```caddyfile
your-domain.com {
	forward_proxy {
		basic_auth myuser myStrongPass   # two inline args, plaintext password is fine
		hide_ip
		hide_via
		# upstream tinyproxy:8888        # uncomment to chain
	}
	respond "Hello" 200
}
```

One more time: don't remove `basic_auth`. An unauthenticated proxy on the public internet gets found and abused within hours.

## Automatic version tracking

`.caddy-version` in this repo is the single source of truth. The `watch-caddy-release` workflow runs every morning, checks the latest release of the upstream Caddy repo, and when a new version appears it bumps the file, commits, triggers a build, and watches the result. If the build fails, the workflow turns red and you get notified.

In other words, when Caddy ships a new version you do nothing — the new image shows up within half a day.

Manual upgrade works the same way: update `.caddy-version` and `CADDY_VERSION` in the Dockerfile, push, then trigger `build-and-push` from the Actions page.

## Local test

With podman or docker installed:

```bash
bash verify.sh ghcr.io/xuzhonglin/caddy-fp:2.11.4
```

The script starts a test container and checks that the plugin is present, that missing or wrong credentials get a 407, and that authenticated plain-HTTP proxying and HTTPS tunneling both work. All four must pass.

Local build (if you're behind the GFW, swap the alpine mirror):

```bash
docker build -t caddy-fp:test \
  --build-arg ALPINE_IMAGE=docker.m.daocloud.io/library/alpine:3.20 .
```

## CI setup

Two repo secrets: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (create under Security on Docker Hub, Read/Write). GHCR uses the built-in GitHub token, nothing to configure.

Two workflows:

- `build-and-push`: smoke test → dual-arch build → push `latest` and version tags to both registries
- `watch-caddy-release`: checks for upstream releases daily and follows them automatically
