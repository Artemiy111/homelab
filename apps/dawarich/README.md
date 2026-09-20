# Dawarich

Dawarich хранит и визуализирует историю местоположений.
URL: `https://dawarich.example.com/`

Разворачивается манифестами в apps/dawarich/k8s/.

## Первый запуск

На пустой базе встроенный seed Dawarich создаёт администратора
`demo@dawarich.app` с паролем `safepassword`. Сразу после первого входа измените
email и пароль в настройках аккаунта.

## Проверка

```sh
curl --resolve dawarich.example.com:443:<node1-ip> \
  -fsS https://dawarich.example.com/api/v1/health
```

Health endpoint должен вернуть JSON со `"status":"ok"`.

## Обновление

Перед обновлением создайте согласованный backup и прочитайте release notes.
