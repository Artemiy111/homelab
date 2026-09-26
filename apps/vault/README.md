# HashiCorp Vault — сервер и синхронизация секретов

Хранилище секретов, динамические учётные данные, transit-шифрование, PKI.
Лицензия — BSL 1.1 (Vault и VSO), у charta-источника она указана в `LICENSE`
репозитория.

Разворачивается **чартом** `hashicorp/vault-helm`, Argo рендерит его сам
(`argocd/applications/vault.yaml`). Ручных манифестов сервера в репозитории
больше нет.

## Состав

| Что | Где | Чем управляется |
|---|---|---|
| Vault-сервер | `argocd/applications/vault.yaml` | Argo (чарт `v0.34.1`, Vault 2.0.4) |
| Vault Secrets Operator | `argocd/applications/vault-secrets-operator.yaml` | Argo (чарт `v1.6.0`) |
| `VaultConnection`, `VaultAuth`, PoC | `apps/vault/k8s/` | `kubectl apply` |
| NetworkPolicy неймспейса Vault | `apps/vault/k8s/networkpolicy.yaml` | `kubectl apply` |
| NetworkPolicy неймспейса VSO | `apps/vault/k8s/networkpolicy-vso.yaml` | `kubectl apply` |
| Маршрут и UI | `platform/homelab/templates/routes/vault.yaml` | чарт `platform/homelab` |
| Скрейп метрик | `apps/victoria-metrics/config/vmagent/scrape.yml` | `kubectl apply` |

Почему чарты берутся из git-репозиториев HashiCorp, а не из
`helm.releases.hashicorp.com`: CDN отдаёт `403` (CloudFront WAF) из этой сети.
ArgoCD умеет рендерить чарт прямо из git, поэтому `repoURL` указывает на
репозиторий, а чарт лежит в его корне (`/`) или в `chart/`.

## Применение

Порядок важен: сначала ArgoCD создаёт оба неймспейса, потом применяются CR.
Неймспейс `vault-secrets-operator` появляется только после синка
`vault-secrets-operator` в Argo, а `kubectl apply` на каталог падает целиком,
если хотя бы один неймспейс ещё не существует.

```sh
# 1. Дождаться, пока ArgoCD создаст namespace vault-secrets-operator
kubectl get namespace vault-secrets-operator

# 2. CR оператора
kubectl apply -f apps/vault/k8s/vaultauth.yaml
kubectl apply -f apps/vault/k8s/poc-vaultstaticsecret.yaml
kubectl apply -f apps/vault/k8s/networkpolicy.yaml
kubectl apply -f apps/vault/k8s/networkpolicy-vso.yaml
```

## Инициализация и unseal

Vault в standalone-режиме требует ручного запуска. Ни одно из этих значений не
должно попадать в git, в issue или в лог.

```sh
kubectl -n vault get pods
kubectl -n vault exec vault-0 -- vault operator init
```

Команда выдаёт unseal-ключи и root token. **Сохранить их вне репозитория.**
Для unseal нужны 3 ключа из 5:

```sh
kubectl -n vault exec -i vault-0 -- vault operator unseal <ключ>
# повторить трижды, затем:
kubectl -n vault exec -i vault-0 -- vault status
```

`vault status` ожидаемо отдаёт exit code 2, пока Vault `sealed`.

Вход в UI:

```sh
kubectl -n vault port-forward svc/vault 8200:8200
export VAULT_ADDR='http://127.0.0.1:8200'
```

UI также доступен на `https://vault.example.com` (TLS терминирует Traefik).

## Первый секрет и роль для VSO

Дальше — только для PoC из `apps/vault/k8s/poc-vaultstaticsecret.yaml`:

```sh
vault secrets enable -path=kv kv-v2
vault kv put kv/poc/probe answer=42

# Политика роли vso-reader из комментария в apps/vault/k8s/vaultauth.yaml
vault policy write vso-reader - <<'HCL'
path "kv/data/poc/*"     { capabilities = ["read"] }
path "kv/metadata/poc/*" { capabilities = ["read", "list"] }
HCL

# audience обязателен на Vault 1.21+; role_name совпадает с
# spec.kubernetes.role в VaultAuth
vault write auth/kubernetes/role/vso-reader \
  bound_service_account_names=vso-vault-auth \
  bound_service_account_namespaces=vault \
  audience=vault \
  policies=vso-reader \
  ttl=1h
```

Пока значение в Vault не заведено, `VaultStaticSecret` не в статусе `synced` —
это ожидаемо, а не ошибка.

## Вход

```sh
export VAULT_ADDR='http://127.0.0.1:8200'
vault login
```

## Важно

- **Auto-unseal не настроен.** После рестарта пода Vault снова `sealed`, и пока
  он sealed, ни один `VaultStaticSecret` не синхронизируется. На KMS в k0s
  вариантов нет, поэтому задача не решена — см. ADR 0005.
- Unseal-ключи и root token хранить **отдельно** от сервера. Резервную копию
  age-ключа пользователь хранит вне репозитория; с Vault то же самое.
- Внутри кластера Vault слушает `8200` без TLS, HTTPS снаружи даёт Traefik.
  Поэтому `VAULT_ADDR` внутри — `http://`, снаружи — `https://`.
- Хранилище — raft на Longhorn (`longhorn-retain`, `Retain`). Смена
  `reclaimPolicy` у StorageClass необратима, а удаление PVC не стирает том
  молча: PV уходит в `Released`, и том остаётся в `volumes.longhorn.io`.
- `/v1/sys/metrics` отдаётся без токена (блок `telemetry` в `listener`).
  В дефолте чарта он закомментирован, и без него vmagent получает 401.
- В кластере сосуществуют четыре системы секретов: Sealed Secrets (канонический
  путь доставки, 40 файлов), SOPS+age (реестр исходных значений), этот Vault и
  Infisical (тестовый). VSO секретов пока не обслуживает.
