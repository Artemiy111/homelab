# Infisical — self-hosted secrets manager

Хранилище переменных окружения для проектов: веб-интерфейс, CLI, доступ по ролям.

## Первый запуск

```sh
bash scripts/bootstrap-platform.sh infisical
```

Затем откройте `https://infisical.example.com` и создайте первого
пользователя (он становится администратором).

`ENCRYPTION_KEY` шифрует хранимые секреты. Его потеря сделает зашифрованные
данные недоступными, поэтому зашифрованный `secrets.enc.env` должен входить
в защищённую копию конфигурации сервера.

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
