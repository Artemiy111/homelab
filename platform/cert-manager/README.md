# cert-manager

Выпуск и ротация TLS-сертификатов из кластера. Эмитент — Let's Encrypt,
challenge — **DNS-01 через RFC2136**: cert-manager пишет TXT-запись
`_acme-challenge.<домен>` в публичную DNS-зону, подписывая обновление
TSIG-ключом. Публичный IP и A/AAAA-запись для этого не нужны — валидация идёт
целиком через DNS, ACME-сервер до узла не стучится.

| | |
|---|---|
| Чарт оператора | `cert-manager` v1.21.2 (`https://charts.jetstack.io`) |
| Namespace | `cert-manager` |
| ClusterIssuer | `letsencrypt-prod`, `letsencrypt-staging` |
| Certificate | `wildcard` в namespace `traefik` → Secret `wildcard-tls` |
| Потребитель | TLSStore `default` (`platform/traefik/tlsstore.yaml`) |

## Почему DNS-01, а не HTTP-01

Порты 80/443 привязаны к адресу узла и не проброшены на роутере, плюс нужен
**wildcard** `*.<домен>`. HTTP-01 и TLS-ALPN-01 wildcard не умеют, а DNS-01 —
умеет и не требует доступа к серверу. Поэтому TXT-запись и RFC2136.

## Устройство

Оператор ставится через Argo (`argocd/applications/cert-manager.yaml`), вместе
с CRD (`crds.enabled: true`, как у cloudnative-pg). `Prune=false` защищает
кластерные CRD от удаления вместе с приложением.

`ClusterIssuer` и `Certificate` — не в Argo-приложении, а в **шаблонах чарта
`platform/homelab`** (`templates/cert-manager/`). Так они рендерятся одной
командой вместе с маршрутами и общим конфигом, и домен берётся из одного места
— `config.domain` в values. Применяются после того, как Argo поднял оператор и
CRD.

| Файл | Что делает |
|---|---|
| `argocd/applications/cert-manager.yaml` | Argo Application: оператор + CRD |
| `platform/homelab/templates/cert-manager/clusterissuers.yaml` | `ClusterIssuer` prod и staging |
| `platform/homelab/templates/cert-manager/certificate.yaml` | `Certificate` `wildcard` на apex + wildcard |

## Установка

```sh
# 1. Оператор и CRD через Argo
kubectl apply -f argocd/applications/cert-manager.yaml
kubectl -n cert-manager get pods    # controller, webhook, cainjector

# 2. Эмитенты и Certificate — из чарта (домен, email, TSIG из values)
helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl apply -f -
```

Домен, `acmeEmail` и `tsigKeyName` — environment-specific и не лежат в Git:
в `values.yaml` плейсхолдеры, реальные значения — в untracked
`values.private.yaml` на сервере.

## TSIG-секрет

Ключ создаётся у DNS-провайдера, алгоритм — HMAC-SHA512 (совпадает с
`tsigAlgorithm` в `values.yaml`). Значение запечатывается `kubeseal` на сервере
— в Git уходит только шифротекст; значение в чат и в открытый вид не выводим.

```sh
kubectl -n cert-manager create secret generic acme-rfc2136-tsig \
  --from-literal=tsig-secret='<значение ключа>' \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > platform/cert-manager/sealedsecret.yaml
```

Имя Secret (`tsigSecretName` в values) должно совпадать с тем, что читает
`ClusterIssuer`.

## Порядок первого выпуска: staging → prod

1. Применить эмитенты и `Certificate` из чарта.
2. Сначала переключить `issuerRef.name` в `certificate.yaml` на
   `letsencrypt-staging`, дождаться `Ready`. Так видно, что DNS-01 и TSIG
   работают, не расходуя лимиты прода.
3. Вернуть `letsencrypt-prod`, Secret `wildcard-tls` перезапишется боевым
   сертификатом.

## Диагностика

```sh
kubectl -n traefik get certificate wildcard
kubectl -n traefik describe certificate wildcard          # Renewal Time
kubectl -n cert-manager get challenge,order,certificaterequest
kubectl -n cert-manager logs deploy/cert-manager --since=10m
```

Если self-check cert-manager не видит TXT из-за внутреннего резолвера (split
horizon) — задать публичный резолвер в values Argo
(`dns01RecursiveNameservers`) или пропустить self-check через
`waitInsteadOfSelfCheck` в solver'е.
