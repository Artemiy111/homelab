# Open WebUI: эксплуатация

## Проверка

```sh
curl --resolve ai.example.com:443:<node1-ip> \
  https://ai.example.com/health
```

Ожидаемый ответ: `{"status":true}`.
