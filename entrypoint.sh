#!/bin/bash
# AmneziaWG 3.0 container entrypoint.
set -uo pipefail

CONF="${AWG_CONF:-/etc/amnezia/amneziawg/awg0.conf}"
IFACE="$(basename "$CONF" .conf)"

log() { echo "[awg] $*"; }

log "starting: conf=$CONF iface=$IFACE"

if [ ! -e /dev/net/tun ]; then
    log "FATAL: /dev/net/tun is missing - cannot create the tunnel"
    exit 1
fi

if [ ! -f "$CONF" ]; then
    log "FATAL: config $CONF not found"
    exit 1
fi

# The host routes the backbone subnet at this container, so it has to forward.
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || log "warn: cannot set ip_forward"

cleanup() {
    log "signal received, bringing the interface down"
    awg-quick down "$CONF" >/dev/null 2>&1
    exit 0
}
trap cleanup TERM INT

if ! awg-quick up "$CONF"; then
    log "FATAL: awg-quick up failed"
    exit 1
fi

log "interface is up:"
awg show 2>&1 | sed 's/^/[awg] /'
ip -br addr show "$IFACE" 2>&1 | sed 's/^/[awg] /'

# Stay in the foreground; if the interface dies, exit so the host restarts us.
while true; do
    sleep 60
    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        log "interface $IFACE disappeared - exiting to trigger a restart"
        exit 1
    fi
done
