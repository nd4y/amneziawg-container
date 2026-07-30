# amneziawg-container

AmneziaWG 3.0 in a container: [`amneziawg-go`](https://github.com/amnezia-vpn/amneziawg-go)
(userspace implementation) together with [`amneziawg-tools`](https://github.com/amnezia-vpn/amneziawg-tools)
(`awg`, `awg-quick`).

The point of this image is hosts that cannot load the AmneziaWG kernel module.
The concrete case it was built for is a **MikroTik RouterOS container** —
RouterOS has no AmneziaWG support of its own, but its containers do expose
`/dev/net/tun`, which is all the userspace implementation needs.

## Image

```
ghcr.io/nd4y/amneziawg-container:latest
```

Built for `linux/amd64` by GitHub Actions. Each build also uploads
`amneziawg.tar.gz` as a workflow artifact, for hosts where importing a plain
image tar is easier than pulling from a registry.

Versions are pinned by build args:

| Arg | Default | What it selects |
|---|---|---|
| `AWGGO_TAG` | `v3.0.2` | `amneziawg-go` release tag |
| `AWGTOOLS_REF` | `master` | `amneziawg-tools` ref (AWG 3.0 parameters are already in `master`) |

## Usage

Mount a config at `/etc/amnezia/amneziawg/awg0.conf` (override the path with
`AWG_CONF`). The entrypoint brings the interface up with `awg-quick`, enables
`ip_forward`, and stays in the foreground so the host can restart it if the
interface dies.

```sh
docker run -d --name awg \
  --cap-add NET_ADMIN --device /dev/net/tun \
  -v /path/to/awg0.conf:/etc/amnezia/amneziawg/awg0.conf:ro \
  ghcr.io/nd4y/amneziawg-container:latest
```

### RouterOS

```
/interface/veth/add name=veth-awg address=192.168.12.5/24 gateway=192.168.12.1
/interface/bridge/port/add bridge=br1-docker interface=veth-awg
/container/add remote-image=ghcr.io/nd4y/amneziawg-container:latest \
    interface=veth-awg name=awg mounts=awg-conf logging=yes start-on-boot=yes
```

Do **not** pre-create the container's `root-dir` with `/file/add`. RouterOS has
to create that directory itself — if it already exists the container imports
fine but every start fails immediately with `exited with status 255`.

## AWG 3.0 notes

AWG 3.0 adds `HeaderProtectionKey`, `ContentPaddingAddition` and randomised
timing ranges (`RekeyAfterTime`, `RekeyTimeout`, `RejectAfterTime`,
`KeepaliveTimeout`, `MaxHandshakeAttempts`) on top of the 2.0 parameter set
(`Jc/Jmin/Jmax`, `S1`–`S4`, `H1`–`H4`, CPS packets `I1`–`I5`).

With header protection enabled, **`S1`–`S4` must be at least 12**: the ChaCha20
nonce is taken from the first 12 bytes of the S padding and is never transmitted.
Shorter padding silently reads past the padding into the message body, which
weakens the cipher without producing any error.

Obfuscation parameters are per-interface, not per-peer, so every node in a mesh
that shares one interface must use an identical set.
