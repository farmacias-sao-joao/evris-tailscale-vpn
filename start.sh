#!/bin/sh
set -eu

# --- Validate required configuration (fail fast with a clear message) ---
if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    echo "ERROR: TAILSCALE_AUTHKEY is not set." >&2
    echo "Generate an auth key at https://login.tailscale.com/admin/settings/keys" >&2
    echo "and add it as a Railway variable named TAILSCALE_AUTHKEY." >&2
    exit 1
fi

HOSTNAME_VALUE="${TAILSCALE_HOSTNAME:-tailscale-app}"
# Defaults to advertising an exit node. Set TAILSCALE_ADDITIONAL_ARGS=""
# (empty) to disable, or pass other `tailscale up` flags.
ADDITIONAL_ARGS="${TAILSCALE_ADDITIONAL_ARGS:---advertise-exit-node}"

mkdir -p /var/run/tailscale /var/lib/tailscale

# --- Graceful shutdown so Railway redeploys/stops cleanly ---
cleanup() {
    echo "Received stop signal, shutting down tailscaled..."
    kill "${TAILSCALED_PID}" 2>/dev/null || true
    wait "${TAILSCALED_PID}" 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# Userspace networking is required on Railway (no /dev/net/tun, no NET_ADMIN).
tailscaled \
    --state=/var/lib/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --tun=userspace-networking \
    --socks5-server=0.0.0.0:1055 \
    --outbound-http-proxy-listen=0.0.0.0:1055 &
TAILSCALED_PID=$!

echo "Waiting for tailscaled socket..."
until [ -S /var/run/tailscale/tailscaled.sock ]; do
    sleep 0.5
done

echo "Bringing Tailscale up as '${HOSTNAME_VALUE}'..."
until tailscale up \
    --authkey="${TAILSCALE_AUTHKEY}" \
    --hostname="${HOSTNAME_VALUE}" \
    ${ADDITIONAL_ARGS}
do
    echo "Retrying 'tailscale up' in 2s..."
    sleep 2
done

echo "Tailscale is up and running!"
tailscale status || true

# Keep the container alive on tailscaled.
wait "${TAILSCALED_PID}"
