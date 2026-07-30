# AmneziaWG 3.0 — amneziawg-go (userspace) + amneziawg-tools (awg / awg-quick)
#
# Built for hosts that cannot run the AmneziaWG kernel module — in particular
# MikroTik RouterOS containers, which do expose /dev/net/tun and therefore can
# run the userspace implementation.
ARG AWGGO_TAG=v3.0.2
ARG AWGTOOLS_REF=master

FROM golang:1.25-alpine AS gobuild
ARG AWGGO_TAG
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 --branch "${AWGGO_TAG}" https://github.com/amnezia-vpn/amneziawg-go.git .
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/amneziawg-go .

FROM alpine:3.21 AS toolsbuild
ARG AWGTOOLS_REF
RUN apk add --no-cache build-base linux-headers git bash
WORKDIR /src
RUN git clone --depth 1 --branch "${AWGTOOLS_REF}" https://github.com/amnezia-vpn/amneziawg-tools.git .
RUN cd src \
 && make -j"$(nproc)" \
 && make install DESTDIR=/staged PREFIX=/usr \
      WITH_BASHCOMPLETION=no WITH_SYSTEMDUNITS=no WITH_WGQUICK=yes
# Upstream has renamed wg->awg over time; accept either and normalise the names.
RUN mkdir -p /out \
 && { cp /staged/usr/bin/awg /out/awg 2>/dev/null || cp /staged/usr/bin/wg /out/awg; } \
 && { cp /staged/usr/bin/awg-quick /out/awg-quick 2>/dev/null || cp /staged/usr/bin/wg-quick /out/awg-quick; } \
 && ls -la /out

FROM alpine:3.21
RUN apk add --no-cache bash iproute2 iptables openresolv
COPY --from=gobuild   /out/amneziawg-go /usr/bin/amneziawg-go
COPY --from=toolsbuild /out/awg         /usr/bin/awg
COPY --from=toolsbuild /out/awg-quick   /usr/bin/awg-quick
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/bin/amneziawg-go /usr/bin/awg /usr/bin/awg-quick /entrypoint.sh \
 && mkdir -p /etc/amnezia/amneziawg

# awg-quick refuses to use the userspace backend unless told to.
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go \
    WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1 \
    AWG_CONF=/etc/amnezia/amneziawg/awg0.conf

ENTRYPOINT ["/entrypoint.sh"]
