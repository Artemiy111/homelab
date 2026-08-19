# LocalAI

LocalAI provides an OpenAI-compatible API at
`https://localai.example.com`. Traefik is the only ingress: the
container does not publish a host port. Every request must include the API key
from `local-ai/.env`, for example as `Authorization: Bearer <key>`.

The deployment uses the pinned `linux/amd64` CPU image. The server has an AMD
Ryzen 7 6800H with eight physical cores and AVX2. LocalAI chooses its own thread
count, while Docker limits the whole container to 14 CPU units so two of the
server's 16 logical CPUs remain outside its quota. GPU devices are deliberately
not passed through.

## First deployment

Create the secret file and persistent directories on the server:

```sh
cp .env.example .env
openssl rand -hex 32
chmod 0600 .env
install -d -m 0750 \
  ${APPS_STORAGE_PATH:-/storage/apps}/local-ai/models \
  ${APPS_STORAGE_PATH:-/storage/apps}/local-ai/backends \
  ${APPS_STORAGE_PATH:-/storage/apps}/local-ai/configuration \
  ${APPS_STORAGE_PATH:-/storage/apps}/local-ai/data
docker compose config --quiet
docker compose up -d
```

Put the generated value in `LOCALAI_API_KEY`. The persistent directories must
be owned by UID/GID `1000:1000`. Existing models under
`$APPS_STORAGE_PATH/local-ai/models` are retained.

The root filesystem is read-only. Only `/models`, `/backends`,
`/configuration`, `/data`, and the memory-backed `/tmp` are writable. The
container runs as a non-root user, drops every Linux capability, cannot gain
new privileges, cannot use swap, and has bounded memory, CPU, PIDs, and logs.

## Verification

```sh
docker compose ps
docker compose exec api curl --fail http://127.0.0.1:8080/readyz
curl --resolve localai.example.com:443:192.0.2.10 \
  https://localai.example.com/readyz
curl --resolve localai.example.com:443:192.0.2.10 \
  -H "Authorization: Bearer $LOCALAI_API_KEY" \
  https://localai.example.com/v1/models
```

The first readiness transition can take longer while LocalAI scans models or
installs a backend. Failed probes are ignored for the first ten minutes so a
normal startup is not marked unhealthy; a successful probe still makes the
container healthy immediately.
