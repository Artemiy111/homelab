# sure: эксплуатация

## Проверка

```sh
curl -sk --resolve sure.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' https://sure.example.com/
```

Ожидаемый ответ: `302` на `/sessions/new` (форма входа).
