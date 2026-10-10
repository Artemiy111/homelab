# HashiCorp Vault — сервер и синхронизация секретов

## Состав

| Что | Где | Чем управляется |
|---|---|---|
| Vault-сервер | `clusters/casa/platform/vault/app.yaml` | Argo (чарт `v0.34.1`, Vault 2.0.4) |
| Vault Secrets Operator | `clusters/casa/platform/vault-secrets-operator/app.yaml` | Argo (чарт `v1.6.0`) |
| `VaultAuthGlobal`, `VaultConnection`, `VaultAuth`, PoC | `clusters/casa/apps/vault/k8s/` | Argo (`clusters/casa/apps/vault-extras/app.yaml`) |
| `VaultAuth` и `VaultStaticSecret` приложения | `clusters/casa/apps/<сервис>/k8s/` | Argo вместе с приложением |
| NetworkPolicy неймспейса Vault | `clusters/casa/apps/vault/k8s/networkpolicy.yaml` | Argo (`vault-extras`) |
| NetworkPolicy неймспейса VSO | `clusters/casa/apps/vault/k8s/networkpolicy-vso.yaml` | Argo (`vault-extras`) |
| Маршрут и UI | `clusters/casa/apps/vault/k8s/route.yaml` | Argo (`vault-extras`) |

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

## Включение хранилища

```sh
vault secrets enable -path=kv kv-v2
```

Политики, роли и конфигурация метода `kubernetes` управляются terraform.

Пока значение в Vault не заведено, соответствующий `VaultStaticSecret` не в
статусе `synced` — это ожидаемо, а не ошибка.

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
- В кластере сосуществуют четыре системы секретов: Vault через VSO
  (канонический путь доставки), Sealed Secrets (переводится, #345), SOPS+age
  (реестр исходных значений) и Infisical (тестовый).
