# Stirling PDF

Stirling PDF — веб-сервис для операций с PDF. Он доступен через Traefik по
адресу `https://pdf.example.net/`; порты контейнера на хост не
публикуются.

Постоянные данные находятся в `/storage/apps/pdf`. Каталог `/configs` содержит
настройки и базу пользователей, поэтому его необходимо включать в резервные
копии. Для первого входа используются `PDF_ADMIN_USERNAME` и
`PDF_ADMIN_PASSWORD` из локального `.env`; после входа пароль следует сменить в
настройках аккаунта.

## Запуск

```sh
cp .env.example .env
chmod 600 .env
install -d /storage/apps/pdf/{configs,customFiles,logs,pipeline,tessdata}
docker compose config --quiet
docker compose up -d
```

Проверка состояния:

```sh
docker compose ps
curl -fsS https://pdf.example.net/api/v1/info/status
```

Образ содержит стандартные OCR-языки. Дополнительные `.traineddata` можно
положить в `/storage/apps/pdf/tessdata`.
