# Stirling PDF: эксплуатация

## Первый вход

Для первого входа используются `PDF_ADMIN_USERNAME` и `PDF_ADMIN_PASSWORD` из
секретов сервиса; после входа пароль следует сменить в настройках аккаунта.

## Проверка

```sh
curl -fsS https://pdf.example.com/api/v1/info/status
```
