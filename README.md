# Домашний сервер

Конфигурация домашнего сервера Fedora Server 44.
Всё рабочее окружение — один узел Kubernetes (k0s); декларативные манифесты
лежат в этом репозитории, а кластер приводится к ним применением манифестов
и через GitOps-стенд. Репозиторий ведётся как учебный проект по
production-практикам DevOps.

## Платформа

| Компонент | Роль | Каталог |
| --- | --- | --- |
| k0s | Single-node Kubernetes: Calico CNI, embedded etcd, CoreDNS | `platform/k0s/` |
| Traefik | Единый ingress: 80/443 через `externalIPs` | `platform/traefik/` |
| Technitium DNS | Локальный DNS, wildcard-зона `*.example.com` | `apps/technitium/` |
| sealed-secrets | Секреты в Git в зашифрованном виде | `argocd/applications/sealed-secrets.yaml` |
| Longhorn | CSI-хранилище: снапшоты, клоны, RWX, бэкапы | `platform/longhorn/` |
| Argo CD | GitOps-стенд для части платформенных компонентов | `argocd/` |
| Headlamp | Веб-UI кластера | `platform/headlamp/` |
| Radar | Kubernetes UI: топология, ресурсы, GitOps, аудит | `platform/radar/` |
| Tailscale | Удалённый доступ и маршрут в домашнюю сеть | `apps/tailscale/` |
| Ansible | Декларативные пакеты и подготовка хоста | `ansible/` |

## Сервисы

Сервисы работают только в локальной сети и через Tailscale, по HTTPS, и
маршрутизируются Traefik'ом. Локальный Technitium DNS разрешает зону
`example.com` и все её поддомены на IP сервера, поэтому проброс портов
53, 80 и 443 на роутере не требуется.

### Инфраструктура

| Сервис | Назначение | Хост |
| --- | --- | --- |
| Zitadel | Identity provider и SSO (основной) | `id.example.com` |
| Authentik | Identity provider и SSO (тестовый стенд) | `auth.example.com` |
| oauth2-proxy | Forward auth для сервисов без своего входа | `oauth.example.com` |
| Traefik dashboard | Панель ingress и API | `traefik.example.com` |
| Technitium DNS | DNS-сервер и блокировка рекламы | `dns.example.com` |
| Homepage | Стартовая страница сервисов | `home.example.com` |
| Headlamp | Веб-UI кластера | `headlamp.example.com` |
| Radar | Kubernetes UI | `radar.example.com` |
| Argo CD | GitOps-контроллер | `argocd.example.com` |
| Longhorn | UI хранилища | `longhorn.example.com` |
| Vault | HashiCorp Vault: секреты, transit, PKI | `vault.example.com` |
| Infisical | Self-hosted secrets manager | `infisical.example.com` |
| RustFS | S3-совместимое объектное хранилище | `s3.example.com` |
| PostgreSQL | Веб-админка PostgreSQL (pgweb) | `postgres.example.com` |
| WUD | Отслеживание обновлений образов | `wud.example.com` |
| 3x-ui | Управление личным Xray-прокси | `xui.example.com` |
| Forgejo | Приватный Git-сервис | `forgejo.example.com` |
| code-server | VS Code в браузере | `code.example.com` |

### Приложения

| Сервис | Назначение | Хост |
| --- | --- | --- |
| Immich | Фото- и видеотека | `immich.example.com` |
| Jellyfin | Домашний медиасервер | `jellyfin.example.com` |
| Navidrome | Музыкальная библиотека | `music.example.com` |
| Jitsi Meet | Приватные видеоконференции | `meet.example.com` |
| Element / Matrix | Чат: Synapse + Element Call (LiveKit) | `element.example.com` |
| Nextcloud | Файлы, синхронизация, календарь и контакты | `nextcloud.example.com` |
| Talk HPB | Signaling для Nextcloud Talk | `talk-signaling.example.com` |
| Seafile | Файловая синхронизация и обмен файлами | `seafile.example.com` |
| OnlyOffice | Редактирование DOCX/XLSX для Seafile | `onlyoffice.example.com` |
| Home Assistant | Автоматизация дома | `ha.example.com` |
| Mailserver | Почта Stalwart + веб-почта Bulwark | `mailserver.example.com` |
| Paperless | Документы и OCR | `paperless.example.com` |
| Stirling PDF | Операции с PDF и OCR | `pdf.example.com` |
| Dawarich | История местоположений и карта перемещений | `dawarich.example.com` |
| Lute | Изучение языков через чтение | `lute.example.com` |
| Sure | Личные финансы | `sure.example.com` |
| Mermaid Live Editor | Редактор диаграмм | `mermaid.example.com` |
| Structurizr | Архитектурные диаграммы | `structurizr.example.com` |
| Open WebUI | Чат-интерфейс для LLM (движок пока не подключён) | `ai.example.com` |
| LocalAI | Локальный OpenAI-совместимый инференс (CPU) | `localai.example.com` |

### Наблюдаемость

| Сервис | Назначение | Хост |
| --- | --- | --- |
| VictoriaMetrics | Долгосрочное хранение метрик (TSDB) | `vm.example.com` |
| Grafana | Дашборды поверх VictoriaMetrics | `grafana.example.com` |
| Netdata | Посекундные метрики хоста и контейнеров | `netdata.example.com` |
| Gatus | Декларативный status page | `uptime.example.com` |
| Uptime Kuma | Мониторинг доступности | `kuma.example.com` |
| Beszel | Метрики хоста | `beszel.example.com` |
| GlitchTip | Сбор ошибок приложений (Sentry SDK) | `glitchtip.example.com` |
| Elasticsearch + Kibana | Централизованные логи (Filebeat) | `kibana.example.com` |
| node-exporter | Метрики узла (`node_*`) для vmagent | без UI |
| db-exporters | Экспортеры PostgreSQL / Redis / MariaDB | без UI |
| otel-collector | Приём OTLP и отдача в Prometheus-формате | без UI |

## Структура репозитория

- `apps/<сервис>/` — один каталог на сервис:
  - `k8s/` — Kubernetes-манифесты: Deployment, Service, VaultStaticSecret, PVC и т.д.;
  - `README.md` — как развернуть, проверить и эксплуатировать.
- `platform/<компонент>/` — платформенные манифесты и values (k0s, traefik,
  longhorn, local-storage, cnpg, mariadb, monitoring, headlamp).
- `platform/homelab/` — Helm-чарт общей конфигурации и всех HTTP-маршрутов;
  реальные домен и адрес сервера — в untracked `values.private.yaml`.
- `argocd/` — GitOps-контроллер Argo CD (пробный стенд):
  - `install/values.yaml` — values чарта самого Argo CD;
  - `applications/<компонент>.yaml` — Application на компонент;
  - `README.md` — установка, адопция релизов и приёмы.
- `platform/traefik/` — конфиг самого Traefik: `values.yaml`, `tlsstore.yaml`,
  общие middleware (`oauth2-proxy.middleware.yaml`) и маршрут дашборда.
- `ansible/` — пакеты и подготовка хоста.
- `terraform/<модуль>/` — конфигурация ресурсов вне кластера; один каталог на
  root-модуль, у каждого свой state. Пока пусто, первый модуль — `vault/`
  (`docs/adr/0008-terraform-tool-and-run-location.md`).
- `.forgejo/workflows/` — CI на Forgejo Actions: `commitlint`, `gitleaks`,
  `ansible-lint`, `kubeconform` (валидация манифестов по схемам Kubernetes),
  `actionlint` (валидация самих workflow), `kube-linter` (проверки безопасности
  манифестов по allow-list в `.kube-linter.yaml`).
- `apps/rustfs/artifacts.tsv` — манифест артефактов для CI; их скачивает и
  складывает в RustFS `apps/rustfs/mirror-sync.sh` (CronJob `mirror-sync`,
  применяется через `kubectl apply -k apps/rustfs`).
- `etc/`, `dotfiles/`, `scripts/`, `docs/` — конфиги ОС, шелл, скрипты и
  документация.

Почему слои такие — `docs/adr/0004-repository-layout.md`.

## Доставка изменений

Источник правды — рабочая копия на macOS, порядок всегда следующий:

1. Изменить манифесты локально и закоммитить.
2. На сервере: `git pull --ff-only`.
3. Применить затронутое:
   ```sh
   kubectl apply -f apps/<сервис>/k8s/
   helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl apply -f -
   ```
4. Проверить health, DNS и HTTP-маршрут.

Платформенные компоненты (Traefik, sealed-secrets, Longhorn, Argo CD)
поставляются Helm'ом; порядок их установки и обновления описан в
`platform/<компонент>/README.md` и `argocd/README.md`.

## Секреты

Доставка секретов в кластер — через HashiCorp Vault и оператор VSO:
`apps/<сервис>/k8s/vaultstaticsecret.yaml` синхронизирует Secret из пути
`kv/<сервис>/<секрет>`. Раскладка путей — `docs/adr/0006-vault-secret-path-layout.md`.

Оставшиеся `SealedSecret`: `apps/zitadel/` (исключён из миграции),
`apps/cert-manager/` (вне scope), `apps/image-updates/` (токен не используется).

Расшифровываемого реестра значений в репозитории нет — единственная копия
секретов в Vault. Plaintext-файлы с секретами в репозитории не хранятся.

## Хранилище

- `local-path` — StorageClass по умолчанию для небольших данных;
- `longhorn` / `longhorn-retain` — CSI-тома со снапшотами, клонами, RWX и
  бэкапами (класс без суффикса → `Delete`, `-retain` → `Retain`);
- `local-storage-retain` — статические PV, привязанные к узлу.

Соглашения, ограничения одноузлового Longhorn и типовые сбои —
`platform/longhorn/README.md`.

## Удалённый доступ

Tailscale устанавливается на хост и даёт SSH и доступ к серверу и всей
домашней подсети без проброса портов. Настройка и проверка —
`apps/tailscale/README.md`.
