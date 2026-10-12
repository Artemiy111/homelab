# Structurizr

Structurizr vNext (open-core) — инструмент для диаграмм C4. Сервис развёрнут
в Kubernetes и доступен через Traefik кластера по
адресу `https://structurizr.example.com/` (за oauth2-proxy).

## Образ

Upstream сделал on-premises заглушкой: `structurizr/onpremises:latest` печатает
баннер про миграцию и завершается с кодом 0. Пребилт-образ vNext
(`structurizr/structurizr server`) требует платной лицензии.

Поэтому образ собирается из исходников (open-core, бесплатно): `Dockerfile`
клонирует upstream на теге `v2026.06.28`, собирает `server` и кладёт его в
runtime-образ на `eclipse-temurin:21-alpine`.

Контейнер запускается от `user: "1000:1000"` — совпадает с владельцем
`/storage/apps/structurizr` на хосте (artlab), поэтому привилегии root не нужны
(в отличие от старого on-premises-образа). PNG/SVG-экспорт через Playwright в
этой сборке недоступен (нужен тег `-playwright`).

## Конфигурация

Настройки (браузерный DSL-редактор + базовый URL за Traefik) заданы в ConfigMap
`structurizr-properties`, который монтируется в
`/usr/local/structurizr/structurizr.properties`.

Доступ закрыт forward auth (`oauth2-proxy`) на IngressRoute — своей
аутентификации у open-core сборки нет.

DNS-запись `structurizr.${DOMAIN} → <node1-ip>` (IP узла) указывает на
Traefik кластера, поэтому forward auth больше не обходится: он единственная
защита сервиса.

## Рабочие пространства (workspace)

Диаграммы C4 всех сервисов homelab описаны в `homelab.dsl` в этом каталоге.
Файл — источник правды и хранится в Git; схема всех сервисов отрисовывается из
него. Это соответствует разделению «в Git / на сервере»:

- **В Git** (`structurizr/`): `homelab.dsl` (модель, представления, стили).
- **На сервере** (`/storage/apps/structurizr`, в контейнере
  `/usr/local/structurizr`): управляемые сервером данные воркспейса
  `<id>/workspace.json`, версии `workspace-<timestamp>.json`, превью и картинки.
  Сервер хранит их в своём формате, поэтому эти файлы вручную не редактируются.

Сервер не читает DSL напрямую из каталога данных — содержимое публикуется через
workspace API. Сейчас воркспейс `HomeLab` имеет `<id> = 1` и доступен по адресу
`https://structurizr.example.com/workspace/1/diagrams`.

При push сервер обратно отдаёт layout, нарисованный в UI, — перерисовка диаграмм
вручную не теряется. Правки модели делаются только в `homelab.dsl` (Git —
источник правды), иначе следующий push их перезапишет.

Сборка и загрузка образа, создание воркспейса и публикация — в `RUNBOOK.md`.
