# cert-manager

Выпуск и ротация TLS-сертификатов из кластера. Эмитент — Let's Encrypt,
challenge — **DNS-01 через собственный webhook** ([`packages/cert-manager-webhook-dns01`](../../packages/cert-manager-webhook-dns01)):
webhook публикует TXT-запись через REST API DNS-провайдера. Публичный IP и
A/AAAA для этого не нужны — валидация идёт целиком через DNS, ACME-сервер до
узла не стучится.

| | |
|---|---|
| Чарт оператора | `cert-manager` v1.21.2 (`https://charts.jetstack.io`) |
| Namespace | `cert-manager` |
| ClusterIssuer | `letsencrypt-prod`, `letsencrypt-staging` |
| Certificate | `wildcard` в namespace `traefik` → Secret `wildcard-tls` |
| Webhook | Argo Application `dns01-webhook` (OCI-чарт из реестра Forgejo) |
| Потребитель | TLSStore `default` (`platform/traefik/tlsstore.yaml`) |

## Почему DNS-01, а не HTTP-01

Порты 80/443 привязаны к адресу узла и не проброшены на роутере, плюс нужен
**wildcard** `*.<домен>`. HTTP-01 и TLS-ALPN-01 wildcard не умеют, а DNS-01 —
умеет и не требует доступа к серверу.

## Почему свой webhook, а не встроенный RFC2136

У DNS-провайдера зона бесплатная, и RFC2136 там **не поддерживает удаление
записей**: `update add` проходит, а `update delete` всегда отвечает `SERVFAIL`.
Solver'у cert-manager удаление нужно и в `Present`, и в `CleanUp`, поэтому
rfc2136 непригоден. Webhook ходит в REST API провайдера, где удаление есть.

Отдельная тонкость: имя `_acme-challenge.<домен>` у провайдера **зарезервировано
под его собственный выпуск** — запись через API принимается, но не публикуется.
Поэтому challenge-имя **CNAME-ом делегируется** на обычное имя:

```
_acme-challenge.<домен>   CNAME   acme.<домен>     # создаётся один раз вручную
acme.<домен>               TXT     <token>         # пишет/удаляет webhook
```

Let's Encrypt резолвит `_acme-challenge.<домен>`, идёт по CNAME и читает TXT из
`acme.<домен>`. Значение `challengeRecord: acme` в `ClusterIssuer` задаёт это
имя.

## Устройство

Оператор ставится через Argo (`argocd/applications/cert-manager.yaml`), вместе с
CRD (`crds.enabled: true`). `Prune=false` защищает кластерные CRD.

Webhook ставится отдельным Argo Application (`argocd/applications/dns01-webhook.yaml`)
из OCI-чарта, который публикует CI репозитория webhook'а в реестр Forgejo.

`ClusterIssuer` и `Certificate` — в **шаблонах чарта `platform/homelab`**
(`templates/cert-manager/`): рендерятся одной командой с маршрутами и общим
конфигом, домен берётся из `config.domain`.

| Файл | Что делает |
|---|---|
| `argocd/applications/cert-manager.yaml` | Argo Application: оператор + CRD |
| `argocd/applications/dns01-webhook.yaml` | Argo Application: webhook-солвер |
| `platform/homelab/templates/cert-manager/clusterissuers.yaml` | `ClusterIssuer` prod и staging |
| `platform/homelab/templates/cert-manager/certificate.yaml` | `Certificate` `wildcard` (только wildcard) |

## Установка

```sh
# 1. Оператор и CRD
kubectl apply --server-side --field-manager=homelab -f argocd/applications/cert-manager.yaml
kubectl -n cert-manager get pods    # controller, webhook, cainjector

# 2. Webhook-солвер (нужны repo-creds и imagePullSecret, см. ниже)
kubectl apply --server-side --field-manager=homelab -f argocd/applications/dns01-webhook.yaml
kubectl -n cert-manager get pods    # dns01-webhook-...

# 3. Эмитенты и Certificate — из чарта (домен, email из values)
helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl apply --server-side --field-manager=homelab -f -
```

## Секреты

Пакеты реестра Forgejo (образ и OCI-чарт) **публичные** — Argo и kubelet тянут их
анонимно, ни repo-creds, ни imagePullSecret не нужны.

Остаётся один секрет — **токен DNS-провайдера**: Secret в namespace
`cert-manager`, из которого webhook читает переменную `PROVIDER_TOKEN`. Имя
задано в `argocd/applications/dns01-webhook.yaml` (`provider.existingSecret`).
Значение запечатывается `kubeseal` на сервере — в Git уходит только шифротекст.

```sh
kubectl -n cert-manager create secret generic dns01-webhook-token \
  --from-literal=token='<HTTP-токен провайдера>' \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > platform/cert-manager/sealedsecret.yaml
kubectl apply --server-side --field-manager=homelab -f platform/cert-manager/sealedsecret.yaml
```

## Порядок первого выпуска: staging → prod

1. Применить эмитенты и `Certificate` из чарта.
2. Сначала переключить `issuerRef.name` в `certificate.yaml` на
   `letsencrypt-staging`, дождаться `Ready`. Так видно, что DNS-01 и webhook
   работают, не расходуя лимиты прода.
3. Вернуть `letsencrypt-prod`, Secret `wildcard-tls` перезапишется боевым
   сертификатом.

## Диагностика

```sh
kubectl -n traefik get certificate wildcard
kubectl -n traefik describe certificate wildcard          # Renewal Time
kubectl -n cert-manager get challenge,order,certificaterequest
kubectl -n cert-manager logs deploy/cert-manager --since=10m
kubectl -n cert-manager logs deploy/dns01-webhook --since=10m
```

Проверить CNAME-делегирование:

```sh
dig +short _acme-challenge.<домен> CNAME
dig +short _acme-challenge.<домен> TXT
```
