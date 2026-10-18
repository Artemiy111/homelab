# Infisical: эксплуатация

## Первый запуск

Откройте `https://infisical.example.com` и создайте первого
пользователя (он становится администратором).

## Проверка

```sh
curl --resolve infisical.example.com:443:<node1-ip> \
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
