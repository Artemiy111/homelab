# Structurizr

Structurizr vNext (open-core) — инструмент для диаграмм C4. Контейнер доступен
через Traefik по адресу `https://structurizr.example.net/`; порт
приложения напрямую на хост не публикуется. Постоянные данные находятся в
`$APPS_STORAGE_PATH/structurizr`, смонтированном в `/usr/local/structurizr`.

## Образ

Upstream сделал on-premises заглушкой: `structurizr/onpremises:latest` печатает
баннер про миграцию и завершается с кодом 0. Пребилт-образ vNext
(`structurizr/structurizr server`) требует платной лицензии.

Поэтому образ собирается из исходников (open-core, бесплатно): `Dockerfile`
клонирует upstream на теге `v2026.06.28`, собирает `server` и кладёт его в
runtime-образ на `eclipse-temurin:21-alpine`. Пересборка при апдейте:

```sh
# в structurizr/: обновить тег vYYYY.MM.DD в Dockerfile, затем
bash init.sh   # создаёт .env (STRUCTURIZR_HOST из общего DOMAIN)
docker compose build --pull
docker compose up -d
```

Контейнер запускается от `user: "1000:1000"` — совпадает с владельцем
`$APPS_STORAGE_PATH/structurizr` на хосте (artlab), поэтому привилегии root не нужны
(в отличие от старого on-premises-образа). PNG/SVG-экспорт через Playwright в
этой сборке недоступен (нужен тег `-playwright`).

## Конфигурация

Настройки лежат в `structurizr.properties.tpl`; `bash init.sh` генерирует из
него `structurizr.properties` (домен из `DOMAIN`), который монтируется в
`/usr/local/structurizr/structurizr.properties`: включён браузерный DSL-редактор
и задан базовый URL за Traefik.

> Примечание: в `$APPS_STORAGE_PATH/structurizr` лежит пустой файл
> `structurizr.properties` (владелец root) — это артефакт Docker: он создаёт
> файл-заготовку как точку монтирования внутри volume. Рабочий конфиг приходит
> из репозитория; пустой файл можно игнорировать, но не удалять, пока
> контейнер запущен.

Внимание: open-core сборка не имеет встроенной аутентификации — при
необходимости закрыть доступ стоит добавить Traefik middleware (например,
basicauth) на роутер `structurizr`.

## Рабочие пространства (workspace)

Диаграммы C4 всех сервисов homelab описаны в `homelab.dsl` в этом каталоге.
Файл — источник правды и хранится в Git; схема всех сервисов отрисовывается из
него. Это соответствует разделению «в Git / на сервере»:

- **В Git** (`structurizr/`): `homelab.dsl` (модель, представления, стили) и
  `structurizr.properties.tpl` (шаблон, из которого init.sh генерирует
  монтируемый конфиг).
- **На сервере** (`$APPS_STORAGE_PATH/structurizr`, в контейнере
  `/usr/local/structurizr`): управляемые сервером данные воркспейса
  `<id>/workspace.json`, версии `workspace-<timestamp>.json`, превью и картинки.
  Сервер хранит их в своём формате, поэтому эти файлы вручную не редактируются.

Сервер не читает DSL напрямую из каталога данных — содержимое публикуется через
workspace API. Сейчас воркспейс `HomeLab` имеет `<id> = 1` и доступен по адресу
`https://structurizr.example.net/workspace/1/diagrams`. Создание нового
воркспейса и запоминание его `<id>` выполняется один раз:

1. Открыть `https://structurizr.example.net/workspace/create`
   (встроенной аутентификации нет — воркспейс создаётся сразу).
2. Запомнить `<id>` из URL `/workspace/<id>`.

Публикация (после изменения `homelab.dsl`, локально или на сервере после
`git pull --ff-only`):

```sh
# проверка синтаксиса (Structurizr CLI, тот же парсер, что у сервера)
structurizr validate -workspace structurizr/homelab.dsl

# выгрузить воркспейс на сервер
structurizr push -url https://structurizr.example.net/api \
  -id <id> -workspace structurizr/homelab.dsl
```

CLI скачивается с https://github.com/structurizr/cli (jar) либо запускается в
контейнере `eclipse-temurin:21-alpine`. При push сервер обратно отдаёт layout,
нарисованный в UI, — перерисовка диаграмм вручную не теряется. Правки модели
делаются только в `homelab.dsl` (Git — источник правды), иначе следующий push
их перезапишет.
