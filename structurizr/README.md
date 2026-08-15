# Structurizr

Structurizr on-premises — инструмент для диаграмм C4. Контейнер доступен через
Traefik по адресу `https://structurizr.example.net/`; порт приложения
напрямую на хост не публикуется. Постоянные данные находятся в
`/storage/apps/structurizr`, смонтированном в `/usr/local/structurizr`.

> Внимание: upstream объявил on-premises версию устаревшей («will not receive any
> further updates»). Рассматривается миграция на Structurizr vNext.

## Почему нельзя просто снять привилегии

Простое понижение прав для этого образа не работает двумя способами:

- `user: "1000:1000"` — entrypoint `/usr/local/entrypoint.sh` не исполняем для
  постороннего UID (образ рассчитан на запуск от root), контейнер падает с
  `exec: "/usr/local/entrypoint.sh": permission denied`.
- `cap_drop: ALL` + `no-new-privileges:true` при запуске от root — контейнер
  уходит в петлю перезапусков (выход с кодом 0): процесс-модель/entrypoint
  образа несовместимы со снятыми capability.

В итоге оставлена исходная конфигурация (без `user`, `cap_drop` и
`no-new-privileges`). Образ и так не публикует порты на хост и доступен только
через `traefiknet`.
