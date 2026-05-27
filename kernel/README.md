# Kernel Builds

Active kernel folders are thin variant workspaces. Run Docker Compose from the
variant directory:

```sh
cd kernel/bore-flto-pgo
docker compose run --rm kernel-builder
```

Shared Dockerfiles, scripts, Compose service definitions, and common assets live
under `common/`. Variant folders keep only their manifest, patches, profiles,
outputs, and workflow notes.

## Add a CachyOS Variant

1. Create `kernel/<variant>/`.
2. Copy `common/templates/cachyos-variant.env.example` to `kernel/<variant>/variant.env`.
3. Set `VARIANT_NAME`, `VARIANT_PATH`, `VARIANT_DIR`, `KERNEL_REF`,
   `KERNEL_SOURCE_SUBDIR`, and `KERNEL_CONFIG_GLOB`.
4. Add `patches/autofdo.patch`, `patches/kernel.patch`, `patches/config.patch`,
   and any required `profiles/` files.
5. Add `docker-compose.yml`:

```yaml
include:
  - path: ../common/compose/cachyos.yml
    env_file: variant.env
```

For a Propeller variant, add `PROPELLER_REF`, `UBUNTU_IMAGE_DIGEST`,
`LLVM_GPG_FINGERPRINT`, `patches/propeller.patch`, Propeller profile files, and
include:

```yaml
  - path: ../common/compose/cachyos-propeller.yml
    env_file: variant.env
```
