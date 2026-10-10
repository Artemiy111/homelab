# cert-manager

Выпуск и ротация TLS-сертификатов из кластера. Эмитент — Let's Encrypt,
challenge — **DNS-01 через собственный webhook**
([`packages/cert-manager-webhook-dns01`](../../packages/cert-manager-webhook-dns01)):
webhook публикует TXT-запись через REST API DNS-провайдера. Публичный IP и
A/AAAA для этого не нужны — валидация идёт целиком через DNS, ACME-сервер до
узла не стучится.

| | |
|---|---|
| Чарт оператора | `cert-manager` v1.21.2 (`https://charts.jetstack.io`) |
| Namespace | `cert-manager` |
| ClusterIssuer | `letsencrypt-prod`, `letsencrypt-staging` и парные `<имя>-<зона>` |
| Certificate | по одному на домен, в namespace `traefik` |
| Webhook | Argo Application `dns01-webhook` (OCI-чарт из реестра Forgejo) |
| Потребитель | TLSStore `default` (`platform/traefik/tlsstore.yaml`) |

## Провайдеры

Зоны перечислены в `certManager.zones` (`platform/homelab/values.yaml`), на каждую
свой `ClusterIssuer` для prod и staging.

| Зона | Провайдер | Что нужно вручную |
|---|---|---|
| `biplane.casa` | `spaceship` | ничего, кроме credentials |

## Почему DNS-01, а не HTTP-01

Порты 80/443 привязаны к адресу узла и не проброшены на роутере, плюс нужен
**wildcard** `*.<домен>`. HTTP-01 и TLS-ALPN-01 wildcard не умеют, а DNS-01 —
умеет и не требует доступа к серверу.

## Почему свой webhook, а не встроенный RFC2136

У DNS-провайдера зона бесплатная, и RFC2136 там **не поддерживает удаление
записей**: `update add` проходит, а `update delete` всегда отвечает `SERVFAIL`.
Solver'у cert-manager удаление нужно и в `Present`, и в `CleanUp`, поэтому
rfc2136 непригоден. Webhook ходит в REST API провайдера, где удаление есть.
У Spaceship отдельной причины для webhook'а нет — там просто нет RFC2136, зато
есть REST API.

Отдельная тонкость dynv6: имя `_acme-challenge.<домен>` у провайдера
**зарезервировано под его собственный выпуск** — запись через API принимается,
но не публикуется. Поэтому challenge-имя **CNAME-ом делегируется** на обычное
имя:

```
_acme-challenge.<домен>   CNAME   acme.<домен>     # создаётся один раз вручную
acme.<домен>               TXT     <token>         # пишет/удаляет webhook
```

Let's Encrypt резолвит `_acme-challenge.<домен>`, идёт по CNAME и читает TXT из
`acme.<домен>`. Поле `challengeRecord` в `ClusterIssuer` задаёт это имя; у зон без
такого ограничения его нет, и TXT пишется прямо в
`_acme-challenge.<домен>`.

## Устройство

Оператор ставится через Argo (`argocd/applications/cert-manager.yaml`), вместе с
CRD (`crds.enabled: true`). `Prune=false` защищает кластерные CRD.

Webhook ставится отдельным Argo Application (`argocd/applications/dns01-webhook.yaml`)
из OCI-чарта, который публикует CI репозитория webhook'а в реестр Forgejo.

`ClusterIssuer` и `Certificate` — в **шаблонах чарта `platform/homelab`**
(`templates/cert-manager/`): рендерятся одной командой с маршрутами и общим
конфигом, домены берутся из `certManager.zones` и `certManager.certificates`.

| Файл | Что делает |
|---|---|
| `argocd/applications/cert-manager.yaml` | Argo Application: оператор + CRD |
| `argocd/applications/dns01-webhook.yaml` | Argo Application: webhook-солвер |
| `platform/homelab/templates/cert-manager/clusterissuers.yaml` | `ClusterIssuer` prod и staging для каждой зоны |
| `platform/homelab/templates/cert-manager/certificate.yaml` | `Certificate` для каждого домена |
| `platform/cert-manager/vaultauth.yaml` | ServiceAccount и `VaultAuth` для VSO |
| `platform/cert-manager/vaultstaticsecret.yaml` | доставка credentials провайдеров из Vault |

## Установка

```sh
# 1. Оператор и CRD
kubectl apply -f argocd/applications/cert-manager.yaml
kubectl -n cert-manager get pods    # controller, webhook, cainjector

# 2. Webhook-солвер (нужны repo-creds и imagePullSecret, см. ниже)
kubectl apply -f argocd/applications/dns01-webhook.yaml
kubectl -n cert-manager get pods    # dns01-webhook-...

# 3. Эмитенты и Certificate — из чарта (зоны, почта из values)
helm template platform/homelab | kubectl apply -f -
```

## Секреты

Пакеты реестра Forgejo (образ и OCI-чарт) **публичные** — Argo и kubelet тянут их
анонимно, ни repo-creds, ни imagePullSecret не нужны.

Credentials DNS-провайдеров лежат в Vault и доставляются в кластер оператором
VSO через `VaultStaticSecret`. Единственная копия значения — Vault, в
репозитории секрета нет.

| Путь в Vault | Ключи | Destination Secret |
|---|---|---|
| `kv/dns01-webhook/dynv6` | `token` | `dns01-webhook-dynv6-token` |
| `kv/dns01-webhook/spaceship` | `api-key`, `api-secret` | `dns01-webhook-spaceship` |
| `kv/3x-ui/@dns01-webhook/egress` | `XUI_EGRESS_USERNAME`, `XUI_EGRESS_PASSWORD` | `dns01-webhook-egress` |

Имена ключей совпадают с ключами destination Secret'а в чарте webhook'а —
доставка не переименовывает ключи, поэтому при 다른 именах правится
`platform/cert-manager/vaultstaticsecret.yaml`, а не Vault.

## Прокси для Spaceship

API Spaceship закрыт WAF'ом провайдера: из сети стенда любой запрос, включая
документацию, получает `403`, а `api.spaceship.dev` и `api.spaceship.com` не
резолвятся. Поэтому запросы к Spaceship идут через egress-прокси 3x-ui
(`apps/3x-ui/chart/templates/service-xui-egress.yaml`), а подключение
задаётся в `argocd/applications/dns01-webhook.yaml`
(`provider.spaceship.proxyURL`).

Прокси привязан к провайдеру, а не к поду: переменная `HTTPS_PROXY` действовала
бы на оба вызова, и поломка прокси остановила бы ротацию `wildcard` на
`biplane.casa`.

Прокси общий с Gatus, который через него шлёт Telegram-уведомления, поэтому его
доступность — общая точка отказа и для алертов, и для ACME. Проверка
доступности — чек `Xray proxy egress` в Gatus, чинить прокси — #54.

TLS сквозной: прокси видит метаданные соединения, но не содержимое запросов и не
API-ключ.

Учётная запись прокси — отдельная, по одной на потребителя: у gatus своя, у
webhook'а своя. Путь `kv/3x-ui/@dns01-webhook/egress` с ключами
`XUI_EGRESS_USERNAME` и `XUI_EGRESS_PASSWORD`, доставка в Secret
`dns01-webhook-egress`. URL прокси собирается в поде: в
`argocd/applications/dns01-webhook.yaml` это
`http://$(XUI_EGRESS_USERNAME):$(XUI_EGRESS_PASSWORD)@xui-egress…:8440`, и
Kubernetes раскрывает ссылки на объявленные выше переменные. В репозитории в
адресе нет credentials — только имя хоста.

Пароль обязан состоять из букв, цифр и `-`, `_`, `.`: символы `@`, `:`, `/`, `#`,
`%` и пробелы ломают разбор URL. Значение живёт в двух местах — в базе панели
3x-ui и в Vault, — поэтому ротация это два шага: сначала новая пара в панели,
затем Vault и форс-синк VSO. Подробности в `apps/3x-ui/README.md`.

Раскладка путей — ADR 0006, правило 1 «потребитель — владелец»: webhook
единственный пользователь этих кредов. Два пути потому, что значения отзываются
и ротируются независимо; внутри Spaceship ключ и секрет выдаются вместе и
отзываются вместе, поэтому один путь с двумя ключами.

Права (политика `app/dns01-webhook`, роль `dns01-webhook`) описаны в
`infra/terraform/vault` — явные пути, без wildcard. Значение в Vault заводит
пользователь, руками и вне Git.

Применение и проверка доставки:

```sh
kubectl apply -f platform/cert-manager/
kubectl -n cert-manager get vaultstaticsecret
kubectl -n cert-manager get secret dns01-webhook-dynv6-token dns01-webhook-spaceship
```

Секреты необязательны для пода: webhook поднимается без них, и падает только тот
challenge, у чьего провайдера нет credentials. Поэтому зона на dynv6 не мешает
зоне на Spaceship, и наоборот. Обратная сторона: ошибка в имени ключа выглядит
так же, как отсутствие секрета, — `SPACESHIP_API_KEY is not set` в логе webhook'а.
Отличаются они списком ключей в destination Secret'е.

**Credentials, доставленные после старта пода, в под не попадут.** Переменная
окружения читается один раз, при запуске контейнера, а `optional: true` не даёт
поду упасть. Поэтому после первого появления секрета в Vault под нужен
перезапуск, иначе webhook продолжит сообщать `SPACESHIP_API_KEY is not set` при
секрете, который на самом деле есть:

```sh
kubectl -n cert-manager annotate vaultstaticsecret dns01-webhook-spaceship \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite
kubectl -n cert-manager rollout restart deploy/dns01-webhook-cert-manager-webhook-dns01
```

Тот же порядок применим к учётной записи прокси: `dns01-webhook-egress` доставляется
так же, но перезапуск нужен и для него.

Ротация: обновить значение в Vault, дальше VSO перезапишет Secret за
`refreshAfter`. Форсировать без ожидания:

```sh
kubectl -n cert-manager annotate vaultstaticsecret dns01-webhook-spaceship \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite
```

Проверка прав без вывода значений:

```sh
vault read kv/dns01-webhook/spaceship -format=json | jq -r '.data.data | keys'
```

## Порядок первого выпуска: staging → prod

1. Применить эмитенты и `Certificate` из чарта.
2. Для нового домена сначала указать в `certManager.certificates` парный
   staging-эмитент (`letsencrypt-staging-<зона>`), дождаться `Ready`. Так видно,
   что DNS-01 и webhook работают, не расходуя лимиты прода. Сертификат каждого
   домена лежит в своём Secret, поэтому подмена не заденет боевые.
3. Вернуть prod-эмитент, Secret перезапишется боевым сертификатом.

## Диагностика

```sh
kubectl -n traefik get certificate
kubectl -n traefik describe certificate wildcard          # Renewal Time
kubectl -n cert-manager get challenge,order,certificaterequest
kubectl -n cert-manager logs deploy/cert-manager --since=10m
kubectl -n cert-manager logs deploy/dns01-webhook --since=10m
```

Проверить CNAME-делегирование (только для зон dynv6):

```sh
dig +short _acme-challenge.<домен> CNAME
dig +short _acme-challenge.<домен> TXT
```