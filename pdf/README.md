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

## Безопасность

Контейнер работает от не-root пользователя через переменные `PUID=1000` и
`PGID=1000`: entrypoint образа сам выполняет `setpriv`/`su`, понижая права до
`stirlingpdfuser` с этим UID. Дополнительно включён `no-new-privileges:true`.

`cap_drop: ALL` здесь **не работает**: entrypoint для понижения прав вызывает
`setpriv`, которому нужны возможности `CAP_SETUID`/`CAP_SETGID`. Без них получаем
`setpriv: setresuid failed: Operation not permitted` и контейнер завершается с
кодом 127. Поэтому `cap_drop` не используется, а понижение прав достигается
только через `PUID`/`PGID`.
