# Old WSL2 kernel

> [!CAUTION]
> Experimental, for testing only. Builds may be unstable.

## Build

```sh
docker compose run --rm kernel-config   # optional
docker compose run --rm kernel-builder
```

## Install

Remove the old custom modules, then copy the new ones:

```sh
sudo rm -rf /usr/lib/modules/*-lto-keng-WSL2
sudo cp -r ./out/modules/lib/modules/* /usr/lib/modules/
```

On Windows, copy `vmlinux` to `C:\Users\<user>\kernel\vmlinux` and add it to
`C:\Users\<user>\.wslconfig`:

```
[wsl2]
kernel=C:\\Users\\<user>\\kernel\\vmlinux
```

After WSL2 restarts, run `sudo depmod -a $(uname -r)`.

## One-time setup

Enable systemd in `/etc/wsl.conf`:

```
[boot]
systemd=true
```

Create `/etc/modules-load.d/docker-net.conf` with:

```
iptable_filter
iptable_nat
ipt_MASQUERADE
br_netfilter
xt_addrtype
xt_conntrack
ip6table_filter
ip6table_nat
iptable_raw
ip6table_raw
```

## Context switch benchmark

![Context switch benchmark results](./benchmark.png)
