# Dawarich

Dawarich хранит и визуализирует историю местоположений.
URL: `https://dawarich.example.com/`

## Первый запуск

Из корня репозитория:

```sh
bash scripts/bootstrap-platform.sh dawarich
```

На пустой базе встроенный seed Dawarich создаёт администратора
`demo@dawarich.app` с паролем `safepassword`. Сразу после первого входа измените
email и пароль в настройках аккаунта.

## Проверка

```sh
docker compose ps
docker compose exec app wget --header='X-Forwarded-Proto: https' -qO- \
  http://127.0.0.1:3000/api/v1/health
curl --resolve dawarich.example.com:443:192.0.2.10 \
  -fsS https://dawarich.example.com/api/v1/health
```

Health endpoint должен вернуть JSON со `"status":"ok"`.

## Обновление

Перед обновлением создайте согласованный backup, прочитайте release notes и
измените `DAWARICH_VERSION` в `config.env`.
Затем выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
```
