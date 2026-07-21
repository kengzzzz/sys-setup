# Rust Toolchain Container

Keeps `rust`, `cargo` and `gcc` off the host. The crate stays on the host and is
bind-mounted in; only the toolchain lives in the image.

## Setup

```sh
cp .env.example .env
mkdir -p "$(grep '^PROJECT_DIR=' .env | cut -d= -f2-)/out"
docker compose build
```

The `out/` directory has to exist before the first run — Docker would otherwise
create the bind-mount source as root and the container, running as your uid,
could not write into it.

## Use

```sh
docker compose run --rm dev
docker compose run --rm check
docker compose run --rm release
```

## Caching

Three named volumes do the work:

| Volume | Mount | Holds |
| --- | --- | --- |
| `rust-cargo-registry` | `/cargo` | downloaded crates, shared across projects |
| `rust-target-<slug>` | `/target` | build artifacts, one per project |
| `rust-home-dev` | `/home/dev` | shell history, rust-analyzer state |

`target/` is a volume rather than a subdirectory of the bind mount, so the host
checkout stays clean and incremental compilation still survives between runs.
Switching projects means switching `PROJECT_SLUG`, which switches target volumes
rather than invalidating one shared cache.

Drop a project's cache with `docker volume rm rust-target-<slug>`.

## rust-analyzer

`rust-analyzer` is in the image. Point your editor at it through the `dev`
service — it needs the same `/work` path mapping as the build, so a client
configured for a local path will not resolve paths correctly without a
workspace-root remap.
