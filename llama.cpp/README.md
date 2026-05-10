# Build llama.cpp Images

- `docker compose build llama-server`

# Configure Model

- copy `./.env.example` to `./.env`
- edit `./.env`
- set `LLAMA_ARG_HF_REPO` to the Hugging Face model reference you want to use
- set `HF_TOKEN` only if the model repo is gated or private
- adjust `LLAMA_ARG_*` values in `./.env` to tune runtime behavior without editing compose
- set `TS_AUTHKEY` to a Tailscale auth key for the sidecar container
- optional: set `TS_EXTRA_ARGS` if you want to pass extra `tailscale up` flags such as advertised tags
- optional: set `LLAMA_ENV_FILE` only when you want compose to load a different env file

# Run Server

- `docker compose up -d`
- connect to the service over the Tailscale node name `llama-server:${LLAMA_ARG_PORT}`

# Notes

- runtime services use `LLAMA_ARG_HF_REPO` from `./.env`
- downloaded models are cached under `./models/hf-home`
- the first run will download the model into the shared Hugging Face cache
- runtime arguments now live in `./.env` and are passed via llama.cpp's built-in `LLAMA_ARG_*` environment support
- `llama-server` no longer publishes a host port; it is only reachable through the Tailscale sidecar network namespace
- the Tailscale sidecar sets `TS_ACCEPT_DNS=false`, so containers keep Docker's default DNS instead of adopting tailnet DNS settings
