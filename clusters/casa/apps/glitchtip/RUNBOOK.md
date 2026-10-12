# GlitchTip: эксплуатация

## Первый вход

При первом входе зарегистрировать учётную запись администратора.

## Проверка

```sh
curl --resolve glitchtip.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://glitchtip.example.com/auth/login/
```

Ожидаемый ответ: `200`.
