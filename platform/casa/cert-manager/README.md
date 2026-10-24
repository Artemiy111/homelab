# cert-manager

Выпуск и ротация TLS-сертификатов из кластера. Эмитент — Let's Encrypt,
challenge — **DNS-01 через собственный webhook**
([`packages/cert-manager-webhook-dns01`](../../packages/cert-manager-webhook-dns01)):
webhook публикует TXT-запись через REST API DNS-провайдера. Публичный IP и
A/AAAA для этого не нужны — валидация идёт целиком через DNS, ACME-сервер до
узла не стучится.

## Провайдеры

На каждую зону — свой `ClusterIssuer` для prod и staging.

| Зона | Провайдер | Что нужно вручную |
|---|---|---|
| `biplane.casa` | `spaceship` | ничего, кроме credentials |

## Проверка распространения DNS-01

Перед выпуском cert-manager сам проверяет, что TXT-запись видна в DNS. По
умолчанию он берёт рекурсивные резолверы из `resolv.conf`, находит у них
authoritative NS зоны и спрашивает уже их напрямую.

Для этого стенда такая цепочка не работает: зона `<домен>` в Technitium —
split-horizon, публичное делегирование живёт в Spaceship, а `NS`/`SOA` самой
зоны Technitium содержат имя сервера, которое никогда не резолвится снаружи.
Проверка получала это имя как authoritative NS и падала с
`lookup <id>. on <cluster-dns>:53: no such host`, хотя TXT-запись была создана и
видна.

Поэтому в `values.yaml` включены
`--dns01-recursive-nameservers-only` и
`--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53`: проверка смотрит только
в публичные рекурсивные резолверы, то есть видит то же, что увидит Let's
Encrypt. Цена — self-check перестаёт проверять authoritative-серверы
напрямую, для split-horizon это и нужно.

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

Оператор ставится через Argo вместе с CRD (`crds.enabled: true`).
`Prune=false` защищает кластерные CRD.

Webhook ставится отдельным Argo Application из OCI-чарта, который CI
репозитория webhook'а публикует в реестр Forgejo.

`ClusterIssuer` и `Certificate` рендерятся **шаблонами общего чарта `homelab`**
одной командой с маршрутами и общим конфигом; домены берутся из
`certManager.zones` и `certManager.certificates`.

## Прокси для Spaceship

API Spaceship закрыт WAF'ом провайдера: из сети стенда любой запрос, включая
документацию, получает `403`, а `api.spaceship.dev` и `api.spaceship.com` не
резолвятся. Поэтому запросы к Spaceship идут через egress-прокси 3x-ui
(`apps/casa/3x-ui/chart/templates/service-xui-egress.yaml`), а подключение
задаётся в `clusters/casa/argocd/platform/dns01-webhook.yaml`
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
`clusters/casa/argocd/platform/dns01-webhook.yaml` это
`http://$(XUI_EGRESS_USERNAME):$(XUI_EGRESS_PASSWORD)@xui-egress…:8440`, и
Kubernetes раскрывает ссылки на объявленные выше переменные. В репозитории в
адресе нет credentials — только имя хоста.

Раскладка путей — ADR 0006, правило 1 «потребитель — владелец»: webhook
единственный пользователь этих кредов. Два пути потому, что значения отзываются
и ротируются независимо; внутри Spaceship ключ и секрет выдаются вместе и
отзываются вместе, поэтому один путь с двумя ключами.

Права (политика `app/dns01-webhook`, роль `dns01-webhook`) описаны в
`infra/casa/terraform/vault` — явные пути, без wildcard. Значение в Vault заводит
пользователь, руками и вне Git.

Установка, раскладка секретов, ротация и диагностика — в `RUNBOOK.md`.
