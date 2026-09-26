# Инвентаризация секретов: кто какие читает

Дата: 2026-09-26. Данные собраны из репозитория и из живого кластера.

Это не исследование внешних технологий, а описание **текущего состояния**: перечень
секретов в репозитории, кто их читает и из какого неймспейса. Нужно как входные
данные для решения о раскладке путей в Vault (см.
`docs/research/vault-secret-path-layout.md` и ADR 0005).

## Как собирались данные

- Определения: `kind: SealedSecret` в `apps/*/k8s/sealedsecret*.yaml` и
  `platform/cnpg/db-auth.sealedsecrets.yaml`, поле `spec.template.metadata.name`
  плюс `metadata.namespace`.
- Потребление: ссылки `secretKeyRef` и `envFrom.secretRef` в `apps/` и
  `platform/`, плюс подстановки `%{VAR}` в `scrape.yml` vmagent.
- Сверка значений: сравнение SHA-256 первых 12 символов, сами значения не
  читались в вывод.

## Три категории, а не одна

Главный вывод обследования: секреты в репозитории лежат **тремя разными
механизмами доставки**, и каждый со своими правилами.

### A. Секреты приложения (≈35 штук)

SealedSecret лежит в неймспейсе приложения, под читающим его подом. Правило
простое: `ns Secret == ns Pod`. Кросс-неймспейсных ссылок нет, Kubernetes их и
не позволяет.

Примеры: `nextcloud`, `authentik`, `immich`, `seafile` (7 ключей), `sure`
(9 ключей), `jitsi`, `element`, `home-assistant`.

### B. Реестр паролей ролей CNPG (1 файл, 15 ролей)

`platform/cnpg/db-auth.sealedsecrets.yaml` создаёт 15 Secret-ов вида
`<app>-db-auth` в неймспейсе `databases`. Их читает **не приложение, а
оператор** — через `spec.managed.roles[].passwordSecret.name` в
`platform/cnpg/shared.cluster.yaml`:

```yaml
managed:
  roles:
    - name: nextcloud
      ensure: present
      login: true
      passwordSecret:
        name: nextcloud-db-auth
```

Роли: `authentik`, `dawarich`, `element`, `forgejo`, `gatus`, `glitchtip`,
`grafana`, `immich`, `infisical`, `nextcloud`, `openwebui`, `paperless`,
`postgres`, `sure`, `zitadel`.

### C. Сквозные инфраструктурные

| Секрет | Где определён | Кто читает |
|---|---|---|
| `cert-manager/dns01-webhook-token` | `platform/cert-manager/sealedsecret.yaml` | вебхук ACME DNS-01, деплоится Argo в `cert-manager` (`existingSecret: dns01-webhook-token`) |
| `monitoring/vmagent` (8 ключей) | `apps/victoria-metrics/k8s/sealedsecret.yaml` | сам vmagent, через `%{VAR}` в `scrape.yml` |
| `databases/nextcloud-db-auth` (30 ключей в одном файле) | `platform/cnpg/db-auth.sealedsecrets.yaml` | CNPG |

## Дубль №1: базовые пароли хранятся дважды

Это самая значимая находка обследования, и она подтверждена сверкой значений.

Цепочка для `nextcloud`:

```
databases/nextcloud-db-auth        ← provisioning: CNPG создаёт роль с этим паролем
        │                              (managed.roles[].passwordSecret)
        │  значение дублируется вручную
        ▼
nextcloud/nextcloud                ← доставка: под приложения читает отсюда
        └─ env POSTGRES_PASSWORD
```

Сверка: `nextcloud/nextcloud` → `POSTGRES_PASSWORD` и
`databases/nextcloud-db-auth` → `password` дали одинаковый хэш
`6406bccb5fe6`. **Значение совпадает, то есть хранится в двух местах.**

Такой же дубль есть минимум у 14 из 15 ролей: у каждой, где в
`apps/<app>/k8s/sealedsecret.yaml` лежит Secret с именем `<app>`.

Чем это опасно:

- правка в одном месте без правки второго ломает приложение или роль;
- SealedSecret необратим, поэтому «исправить» можно только перевыпустив
  оба шифротекста;
- при ротации нужно помнить про оба файла, а не про один.

Для сравнения: `grafana-db-auth` (роль CNPG) и `grafana-db` (приложение) — это
**разные** Secret-и с разными именами, и связь между ними нигде не описана.
То есть на 15 ролей приходится два соглашения об именовании.

## Дубль №2: хаб креденшелов мониторинга

`monitoring/vmagent` — единственный Secret, в котором лежат ключи **семи
чужих сервисов**:

| Ключ в Secret `vmagent` | Чей это ключ |
|---|---|
| `LOCALAI_API_KEY` | local-ai |
| `HOME_ASSISTANT_TOKEN` | home-assistant |
| `UPTIME_KUMA_METRICS_API_KEY` | uptime-kuma |
| `NAVIDROME_METRICS_PATH` | navidrome (случайный суффикс к `/metrics_`, `ND_PROMETHEUS_METRICSPATH`) |
| `DAWARICH_METRICS_PASSWORD` | dawarich |
| `FORGEJO_METRICS_TOKEN` | forgejo |
| `TECHNITIUM_METRICS_TOKEN` | technitium |
| `STALWART_METRICS_PASSWORD` | mailserver (stalwart) |

Потребление — не через `secretKeyRef`, а подстановкой в конфиг:

```yaml
# apps/victoria-metrics/config/vmagent/scrape.yml
- job_name: uptime-kuma
  basic_auth:
    password: "%{UPTIME_KUMA_METRICS_API_KEY}"
```

Это самая концентрированная точка межсервисного разделения секретов в
репозитории. Из неё следуют два наблюдения:

1. `NAVIDROME_METRICS_PATH` секретом не является вообще — это путь до
   эндпоинта, ему место в ConfigMap.
2. vmagent — единственный потребитель, которому нужны права сразу на семь
   префиксов. При наивной раскладке `kv/<владелец>/` это означает либо семь
   точечных правил в его политике, либо один широкий wildcard, что хуже.

## Кросс-неймспейсных ссылок нет

Отдельный результат проверки: **ни одно `secretKeyRef` не ссылается на Secret
из другого неймспейса.** Так и не может быть — Kubernetes такое не умеет.
Все кросс-сервисные передачи идут через описанные выше дубли и через
`databases`, а не через прямые ссылки.

Это важно для выбора раскладки: раскладку, при которой Secret лежит в одном
неймспейсе, а читает другой, технически реализовать **нельзя** без
промежуточного шага. Значит либо секрет дублируется (как сейчас), либо
дублируются `VaultStaticSecret`-объекты, ссылающиеся на один путь в Vault.

## Что из этого следует для раскладки

| Находка | Следствие для раскладки |
|---|---|
| Категория A, правило `ns Secret == ns Pod` | `kv/<app>/…` работает напрямую, по одному `VaultStaticSecret` на секрет в своём неймспейсе |
| Дубль №1 (пароли ролей CNPG) | один путь `kv/<app>/db`, **два** `VaultStaticSecret` в разных неймспейсах читают его. Дубль исчезает, источник истины один |
| Дубль №2 (хаб vmagent) | либо политика из семи точечных `path`, либо `x/<потребитель>/`-схема. Wildcard на `kv/*/*` недопустим |
| `dns01-webhook-token` | инфраструктурный, свой префикс; читает вебхук в `cert-manager`, а не `platform/cert-manager` |

## Что не проверено

- ansible (`ansible/host.yml`) и `dotfiles/` могут читать секреты в обход
  Kubernetes — не обследовано. Для Vault это отдельный класс потребителей:
  ему нужен не `VaultStaticSecret`, а токен или CLI-доступ.
- Forgejo Actions: `apps/forgejo/k8s/runner.configmap.yaml` может получать
  секреты иным способом — не проверялось.
- Полный перечень ключей в каждом Secret не разбирался: важна структура
  доставки, а не значения.

## Связанные документы

- `docs/research/vault-secret-path-layout.md` — как раскладывают пути и ACL,
  со ссылками на документацию.
- `docs/adr/0005-vault-secrets-operator.md` — почему выбран VSO, и миграция на
  ESO.
- `docs/agents/server-access.md` — почему `secrets.enc.env` остаётся реестром
  исходных значений.
