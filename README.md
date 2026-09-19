# Домашний сервер

Конфигурация домашнего сервера Fedora Server 44 по адресу `192.0.2.10`.
Всё рабочее окружение — один узел Kubernetes (k0s); декларативные манифесты
лежат в этом репозитории, а кластер приводится к ним применением манифестов
и через GitOps-стенд. Репозиторий ведётся как учебный проект по
production-практикам DevOps.

## Платформа

| Компонент | Роль | Каталог |
| --- | --- | --- |
| k0s | Single-node Kubernetes: Calico CNI, embedded etcd, CoreDNS | `k8s/k0s/` |
| Traefik | Единый ingress: 80/443 на `192.0.2.10` через `externalIPs` | `k8s/traefik/` |
| Technitium DNS | Локальный DNS, wildcard-зона `*.example.com` | `apps/technitium/` |
| sealed-secrets | Секреты в Git в зашифрованном виде | `k8s/sealed-secrets/` |
| Longhorn | CSI-хранилище: снапшоты, клоны, RWX, бэкапы | `k8s/longhorn/` |
| Argo CD | GitOps-стенд для части платформенных компонентов | `k8s/argocd/` |
| Headlamp | Веб-UI кластера | `k8s/headlamp/` |
| Tailscale | Удалённый доступ и маршрут в домашнюю сеть | `apps/tailscale/` |
| Ansible | Декларативные пакеты и подготовка хоста | `ansible/` |

## Сервисы

Сервисы работают только в локальной сети и через Tailscale, по HTTPS, и
маршрутизируются Traefik'ом. Локальный Technitium DNS разрешает зону
`example.com` и все её поддомены в `192.0.2.10`, поэтому проброс портов
53, 80 и 443 на роутере не требуется.

Общие для сервисов значения (`DOMAIN`, `DEFAULT_LOCALE`) приходят из
кластерного ConfigMap `homelab-config` (в Git не трекается); хосты в манифестах
заданы литерально.

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
  - `k8s/` — Kubernetes-манифесты: Deployment, Service, SealedSecret, PVC и т.д.;
  - `README.md` — как развернуть, проверить и эксплуатировать;
  - `config.env` — публичная конфигурация сервиса (plaintext, tracked);
  - `secrets.enc.env` — наследие Docker Compose (SOPS + age); в доставке не
    участвует, поддерживается как расшифровываемый реестр значений секретов.
- `k8s/<компонент>/` — платформенные манифесты и values (k0s, traefik,
  sealed-secrets, storage, argocd, headlamp).
- `k8s/traefik/<сервис>.ingress*.yaml` — маршрут Traefik для сервиса.
- `ansible/` — пакеты и подготовка хоста.
- `etc/`, `dotfiles/`, `scripts/`, `docs/` — конфиги ОС, шелл, скрипты и
  документация.

Историческое наследие миграции: `apps/<сервис>/compose.yaml`, `init.sh` и
скрипты в `scripts/` относятся к Docker Compose и постепенно выводятся из
эксплуатации. Единственный процесс доставки изменений — Kubernetes-манифесты.
## Доставка изменений

Источник правды — рабочая копия на macOS, порядок всегда следующий:

1. Изменить манифесты локально и закоммитить.
2. На сервере: `git pull --ff-only`.
3. Применить затронутое:
   ```sh
   kubectl apply -f apps/<сервис>/k8s/
   kubectl apply -f k8s/traefik/<сервис>.ingress*.yaml
   ```
4. Проверить health, DNS и HTTP-маршрут.

Платформенные компоненты (Traefik, sealed-secrets, Longhorn, Argo CD)
поставляются Helm'ом; порядок их установки и обновления описан в
`k8s/<компонент>/README.md` и `k8s/argocd/README.md`.

## Секреты

Доставка секретов в кластер — только SealedSecret
(`apps/<сервис>/k8s/sealedsecret.yaml`). Контроллер sealed-secrets в
`kube-system` расшифровывает их в обычные Secret внутри кластера.

Файлы `apps/<сервис>/secrets.enc.env` (SOPS + age) — наследие эпохи Docker
Compose, в доставке они не участвуют, но поддерживаются в актуальном состоянии
как расшифровываемый реестр значений: SealedSecret необратим, а `secrets.enc.env`
позволяет достать исходные значения. Приватный age-ключ существует только на
сервере, в Git лежит лишь публичный.

Plaintext-файлы с секретами в репозитории не хранятся. Подробности —
`docs/agents/server-access.md`.

## Хранилище

- `local-path` — StorageClass по умолчанию для небольших данных;
- `longhorn` / `longhorn-retain` — CSI-тома со снапшотами, клонами, RWX и
  бэкапами (класс без суффикса → `Delete`, `-retain` → `Retain`);
- `local-storage-retain` — статические PV, привязанные к узлу.

Соглашения, ограничения одноузлового Longhorn и типовые сбои —
`k8s/longhorn/README.md`.

## Удалённый доступ

Tailscale устанавливается на хост и даёт SSH и доступ к `192.0.2.10` и всей
подсети `192.0.2.10/24` без проброса портов. Настройка и проверка —
`apps/tailscale/README.md`.

## Временный доступ к веб-панели роутера

Роутер (`192.0.2.10`) доступен только из локальной сети. Из tailnet-клиента
панель напрямую не открывается: в tailnet объявлен маршрут лишь на
`192.0.2.10/24`. Проброс `ssh -L` тоже не работает — SELinux на сервере
запрещает `sshd_session_t` исходящие соединения (`name_connect`), и проброс
падает с `connect failed` / `Connection reset by peer`.

Обходной путь на время — релей `ncat` на самом сервере, привязанный к его
Tailscale-адресу. Запускать в foreground в обычной ssh-сессии: процесс живёт,
пока открыт терминал, и завершается по `Ctrl+C` (или вместе с сессией). Без
`nohup`, `setsid` и `&`, иначе он останется висеть после выхода.

На сервере:

```sh
ncat -lk "$(tailscale ip -4)" 18080 --sh-exec "ncat 192.0.2.10 80"
```

На клиенте открыть в браузере `http://<tailscale-ip-сервера>:18080/`
(IP показан в выводе `tailscale ip -4` на сервере; здесь это адрес сервера, а
не клиента). Проверка:

```sh
curl -o /dev/null -sS -w '%{http_code}\n' http://<tailscale-ip-сервера>:18080/
```

Релей не аутентифицирует запросы: пока процесс запущен, админка роутера
доступна любому устройству в tailnet. Поэтому только временно. Постоянный
доступ требует отдельного решения — SELinux-модуль для `ssh -L` либо
публикация панели через Traefik с авторизацией.
