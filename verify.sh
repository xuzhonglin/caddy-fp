#!/usr/bin/env bash
# Caddy forwardproxy 镜像验证脚本（Podman/Docker 通用）
# 用法: bash verify.sh [镜像tag，默认 localhost/caddy-forwardproxy:test]
set -e

IMAGE="${1:-localhost/caddy-forwardproxy:test}"
HOST_PORT=18888          # 避免 8888 等常见端口被本机其他代理工具占用
PROXY_ADDR="localhost:$HOST_PORT"   # 用 localhost 而非 127.0.0.1（podman 可能只绑 IPv6 回环）

# 关键：清掉环境代理变量，否则 curl 的 -x 会被干扰，结果失真
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

echo "===== 1/6 确认 forward_proxy 插件 ====="
if "$([ -x /usr/bin/podman ] && echo podman || echo docker)" run --rm "$IMAGE" list-modules | grep -q forward_proxy; then
  echo "OK: http.handlers.forward_proxy 已加载"
else
  echo "FAIL: 未找到 forward_proxy 插件"; exit 1
fi

RUN="podman"
command -v podman >/dev/null || RUN=docker

echo
echo "===== 2/6 启动测试容器 (宿主 $HOST_PORT -> 容器 8888) ====="
$RUN rm -f caddy-fp-test >/dev/null 2>&1 || true
$RUN run -d --name caddy-fp-test -p $HOST_PORT:8888 \
  -v "$PWD/test-Caddyfile:/etc/caddy/Caddyfile:ro" \
  "$IMAGE" >/dev/null
sleep 3

pass=0; fail=0
check() { [ "$2" = "$3" ] && { echo "PASS: $1"; pass=$((pass+1)); } || { echo "FAIL: $1 (实际=$2, 期望=$3)"; fail=$((fail+1)); }; }

echo
echo "===== 3/6 无认证访问（期望 407）====="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -x "http://$PROXY_ADDR" http://httpbin.org/ip || echo err)
check "认证强制开启" "$code" "407"

echo
echo "===== 4/6 错误密码（期望 407）====="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -x "http://$PROXY_ADDR" -U myuser:wrongpass http://httpbin.org/ip || echo err)
check "密码校验生效" "$code" "407"

echo
echo "===== 5/6 带认证走明文 HTTP 代理 ====="
body=$(curl -s --max-time 20 -x "http://$PROXY_ADDR" -U myuser:myStrongPass http://httpbin.org/ip || true)
echo "返回: $body"
echo "$body" | grep -q origin && { echo "PASS: 明文代理转发正常"; pass=$((pass+1)); } || { echo "FAIL"; fail=$((fail+1)); }

echo
echo "===== 6/6 带认证 CONNECT 隧道走 HTTPS ====="
ip=$(curl -s --max-time 20 -x "http://$PROXY_ADDR" -U myuser:myStrongPass https://ipinfo.io/ip || true)
echo "出口 IP: $ip"
[ -n "$ip" ] && { echo "PASS: HTTPS 隧道正常"; pass=$((pass+1)); } || { echo "FAIL"; fail=$((fail+1)); }

echo
$RUN rm -f caddy-fp-test >/dev/null
echo "======================================="
echo " 结果: $pass 通过, $fail 失败"
[ $fail -eq 0 ] && echo " 镜像可用，正向代理配置正确 ✅"
echo "======================================="
exit $fail
