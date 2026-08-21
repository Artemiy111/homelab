# Infisical — self-hosted secrets manager

Open-source secrets management platform (MIT CE). Хранение, ротация и
доставка секретов через Web UI, CLI и SDK.

## Архитектура

- **PostgreSQL 14** — данные и зашифрованные секреты
- **Redis 7** — кэш и очереди задач
- **Infisical backend** — API + Web UI (порт 8080)

## Первый запуск

`init.sh` создаёт каталоги данных, формирует локальный `infisical/.env`
(пароль PostgreSQL, `ENCRYPTION_KEY`, `AUTH_SECRET` и `TRUSTED_PROXY_CIDRS`)
и проверяет Compose-конфигурацию. Секреты не попадают в Git.

```sh
cd /home/artlab/projects/homelab
bash infisical/init.sh
cd infisical
docker compose up -d
docker compose ps
```

Затем откройте `https://infisical.example.com` и создайте первого
пользователя (он становится администратором).

`ENCRYPTION_KEY` шифрует хранимые секреты. Его потеря сделает зашифрованные
данные недоступными, поэтому `.env` должен входить в защищённую копию
конфигурации сервера.

## Проверка

```sh
docker compose ps
curl --resolve infisical.example.com:443:192.0.2.10 \
  -fsS https://infisical.example.com/api/status
```

`/api/status` должен вернуть JSON с `"message":"Ok"` и HTTP 200.

## CLI

```sh
npm install -g @infisical/cli
infisical login --domain https://infisical.example.com
infisical init
infisical run --env=dev -- node app.js
```

## Бэкап

```sh
docker compose exec postgres pg_dump -U infisical infisical > backup.sql
```

**Важно:** сохранять `ENCRYPTION_KEY` отдельно — без него расшифровка невозможна.
