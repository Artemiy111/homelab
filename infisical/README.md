# Infisical — self-hosted secrets manager

Open-source secrets management platform (MIT CE). Хранение, ротация и
доставка секретов через Web UI, CLI и SDK.

## Архитектура

- **PostgreSQL 14** — данные и зашифрованные секреты
- **Redis 7** — кэш и очереди задач
- **Infisical backend** — API + Web UI (порт 8080)

## Запуск

1. Скопировать `.env.example` в `.env` и сгенерировать ключи:

```sh
ENCRYPTION_KEY=$(openssl rand -hex 16)
AUTH_SECRET=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -hex 24)
```

2. Запустить:

```sh
docker compose up -d
```

3. Открыть `https://infisical.example.net` и создать
   первого пользователя (он становится администратором).

## CLI

```sh
npm install -g @infisical/cli
infisical login --domain https://infisical.example.net
infisical init
infisical run --env=dev -- node app.js
```

## Бэкап

```sh
docker compose exec postgres pg_dump -U infisical infisical > backup.sql
```

**Важно:** сохранять `ENCRYPTION_KEY` отдельно — без него расшифровка невозможна.
