# Beszel: эксплуатация

## Первый запуск

Откройте URL и создайте администратора. Затем:

1. В Settings → Tokens создайте universal token.
2. Запишите значения в Vault:

```
BESZEL_AGENT_KEY = ssh-ed25519 AAAA...
BESZEL_AGENT_TOKEN = секретный-токен
```

Если система не добавилась автоматически, создайте её через Add System и укажите
`/beszel_socket/beszel.sock` как Host / IP. После запуска проверьте
HTTPS-маршрут:

```sh
curl -fsS https://beszel.example.com/api/health
```
