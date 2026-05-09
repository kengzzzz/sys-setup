# Build llama.cpp Images

- `docker compose build llama-server`
- `docker compose build llama-completion`

# Configure Model

- copy `./.env.example` to `./.env`
- edit `./.env`
- set `MODEL_HF_REPO` to the Hugging Face model reference you want to use
- set `HF_TOKEN` only if the model repo is gated or private

# Run Server

- `docker compose up llama-server`

# Run Completion Interactively

- `docker compose run --rm llama-completion`

# Notes

- runtime services use `-hf ${MODEL_HF_REPO}` from `./.env`
- downloaded models are cached under `./models/hf-home`
- the first run of either service will download the model into the shared Hugging Face cache
- runtime arguments now live in `docker-compose.yml` instead of the Dockerfile
