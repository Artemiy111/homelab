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
`stirlingpdfuser` с этим UID. Включён `no-new-privileges:true`.

Дополнительно применяется «точечное» деление привилегий — `cap_drop: ALL` с
возвратом только тех capability, которые образ реально использует:

- `CAP_SETUID` / `CAP_SETGID` — entrypoint вызывает `setpriv` для понижения прав;
- `CAP_CHOWN` — правка владельца смонтированных томов;
- `CAP_DAC_OVERRIDE` — не-root пользователь создаёт рабочие каталоги
  (`/home/stirlingpdfuser`, `/tmp/stirling-pdf`, кэши) внутри путей, принадлежащих
  root.

Простое `cap_drop: ALL` без этих capability ломает запуск: `setpriv` падает с
`setresuid failed: Operation not permitted` (нет `SETUID`/`SETGID`) либо приложение
не может создать свои каталоги (нет `DAC_OVERRIDE`). Поэтому сбрасываются все
capability, а возвращаются ровно перечисленные четыре.
