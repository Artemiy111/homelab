# Element / Matrix: эксплуатация

## Первый администратор

Публичная регистрация отключена. Первого администратора создают вручную;
пользователь входит в Element под своим логином и паролем, а его Matrix ID
получает вид `@YOUR_LOGIN:example.com`.

## Проверка

```sh
curl -fsS https://element.example.com/_matrix/client/versions
curl -fsS https://element.example.com/livekit/jwt/healthz
```

Полная проверка Element Call требует двух авторизованных клиентов в LAN или
tailnet: создать комнату, начать звонок и проверить аудио/видео.
