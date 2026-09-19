# Infisical — self-hosted secrets manager

Хранилище переменных окружения для проектов: веб-интерфейс, CLI, доступ по ролям.

Разворачивается манифестами в apps/infisical/k8s/.

## Первый запуск

Откройте `https://infisical.example.com` и создайте первого
пользователя (он становится администратором).

`ENCRYPTION_KEY` шифрует хранимые секреты. Его потеря сделает зашифрованные
данные недоступными, поэтому зашифрованный `secrets.enc.env` должен входить
в защищённую копию конфигурации сервера.

## Проверка

```sh
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
