# Structurizr

Structurizr vNext (open-core) — инструмент для диаграмм C4. Сервис развёрнут
в Kubernetes (`apps/structurizr/k8s/`) и доступен через Traefik кластера по
адресу `https://structurizr.example.com/` (за oauth2-proxy). В Docker
(`compose.yaml`) осталась только сборка образа.

## Образ

Upstream сделал on-premises заглушкой: `structurizr/onpremises:latest` печатает
баннер про миграцию и завершается с кодом 0. Пребилт-образ vNext
(`structurizr/structurizr server`) требует платной лицензии.

Поэтому образ собирается из исходников (open-core, бесплатно): `Dockerfile`
клонирует upstream на теге `v2026.06.28`, собирает `server` и кладёт его в
runtime-образ на `eclipse-temurin:21-alpine`. Пересборка при апдейте:

```sh
bash apps/structurizr/init.sh   # рендерит properties из общего DOMAIN
# в apps/structurizr/: обновить тег vYYYY.MM.DD в Dockerfile, затем
docker compose build --pull
```

Готового образа в registry нет, а сервис работает в k8s, поэтому после сборки
образ нужно загрузить в containerd k0s и перезапустить деплоймент:

```sh
docker tag structurizr-structurizr:latest localhost/structurizr:2026.06.28
docker save localhost/structurizr:2026.06.28 \
  | sudo ctr -a /run/k0s/containerd.sock -n k8s.io images import -
kubectl rollout restart deploy/structurizr
```

Тег `localhost/structurizr:<версия>` должен совпадать с `image` в
`k8s/deployment.yaml`.

Контейнер запускается от `user: "1000:1000"` — совпадает с владельцем
`$APPS_STORAGE_PATH/structurizr` на хосте (artlab), поэтому привилегии root не нужны
(в отличие от старого on-premises-образа). PNG/SVG-экспорт через Playwright в
этой сборке недоступен (нужен тег `-playwright`).

## Конфигурация

Настройки (браузерный DSL-редактор + базовый URL за Traefik) заданы в ConfigMap
`structurizr-properties` (`apps/structurizr/k8s/properties.configmap.yaml`),
который монтируется в `/usr/local/structurizr/structurizr.properties`.

`structurizr.properties.tpl` + `init.sh` — легаси-путь для compose-сборки
(`init.sh` рендерит `structurizr.properties` из `DOMAIN`); в k8s не используются.

Доступ закрыт forward auth (`oauth2-proxy`) на IngressRoute — своей
аутентификации у open-core сборки нет.

## Развёртывание в Kubernetes

Сервис описан манифестами в `apps/structurizr/k8s/`:

- `deployment.yaml` — образ `localhost/structurizr:2026.06.28`
  (`imagePullPolicy: IfNotPresent`), uid/gid 1000, `Recreate`, hostPath-данные
  `/storage/apps/structurizr` + ConfigMap `structurizr-properties`;
- `service.yaml` — ClusterIP, порт 80 → 8080 (Gatus ходит по `http://structurizr/`);
- `k8s/traefik/structurizr.ingressroute.yaml` — `Host(structurizr…)` за
  `oauth2-proxy` (у open-core нет своей аутентификации) + `secure-headers` +
  `ratelimit-default`.

DNS-запись `structurizr.${DOMAIN} → 192.0.2.10` указывает на MetalLB-VIP
Traefik кластера, поэтому forward auth больше не обходится: он единственная
защита сервиса.

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
`https://structurizr.example.com/workspace/1/diagrams`. Создание нового
воркспейса и запоминание его `<id>` выполняется один раз:

1. Открыть `https://structurizr.example.com/workspace/create`
   (встроенной аутентификации нет — воркспейс создаётся сразу).
2. Запомнить `<id>` из URL `/workspace/<id>`.

Публикация (после изменения `homelab.dsl`, локально или на сервере после
`git pull --ff-only`):

```sh
# проверка синтаксиса (Structurizr CLI, тот же парсер, что у сервера)
structurizr validate -workspace structurizr/homelab.dsl

# выгрузить воркспейс на сервер
structurizr push -url https://structurizr.example.com/api \
  -id <id> -workspace structurizr/homelab.dsl
```

CLI скачивается с https://github.com/structurizr/cli (jar) либо запускается в
контейнере `eclipse-temurin:21-alpine`. При push сервер обратно отдаёт layout,
нарисованный в UI, — перерисовка диаграмм вручную не теряется. Правки модели
делаются только в `homelab.dsl` (Git — источник правды), иначе следующий push
их перезапишет.
