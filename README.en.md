[中文](README.md) | English

# caddy-fp

A Caddy image with the forward_proxy plugin built in, available for linux/amd64 and linux/arm64.

The official Caddy distribution does not include forward proxy support, and enabling a plugin requires compiling it from source. This repository performs that build through GitHub Actions: every build runs a functional smoke test first, and images are published to Docker Hub and GHCR only after the test passes.

```
docker pull colinxu/caddy-fp:latest
docker pull ghcr.io/xuzhonglin/caddy-fp:latest
```

## Features

- HTTP forward proxy: plain requests are forwarded using absolute URLs, and HTTPS traffic is carried over CONNECT tunnels. Tunnels are end-to-end encrypted; the proxy cannot inspect the content
- Username/password authentication. The `hide_ip` and `hide_via` options prevent client information from leaking upstream
- Supports chaining through an upstream proxy such as tinyproxy
- Containers run as a non-root user; the image is approximately 60MB

## Deployment

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

Copy the `Caddyfile` from this repository into the deployment directory, update the domain and credentials, then run `docker compose up -d`. TLS certificates are issued and renewed automatically.

Client usage:

```bash
curl -x https://myuser:myStrongPass@your-domain.com https://httpbin.org/ip
```

If the returned IP is the server's egress address rather than your own, the proxy chain is working. In browsers, select HTTPS (secure web proxy) as the proxy type.

Full configuration example:

```caddyfile
your-domain.com {
	forward_proxy {
		basic_auth myuser myStrongPass   # two inline arguments; plaintext password
		hide_ip
		hide_via
		# upstream tinyproxy:8888        # uncomment to chain through an upstream
	}
	respond "Hello" 200
}
```

Note that `basic_auth` must be kept in place. Unauthenticated proxies on the public internet are discovered and abused by scanners within hours.
