# Headlamp

## Вход

Вход через OIDC, без service account-токенов. Headlamp сам ходит в Zitadel
и отдаёт apiserver'у `id_token`, который тот проверяет по подписи. Права
выдаёт claim `role` из токена, а не ServiceAccount пода.

Схема по шагам:

| Шаг | Где |
|---|---|
| Приложение OIDC в Zitadel | `terraform/zitadel/applications.tf` |
| Claim `role` (`admin`/`user`) | `terraform/zitadel/actions.tf` |
| Доверие apiserver к Zitadel | `etc/k0s/k0s.yaml.j2`, `spec.api.extraArgs` |
| `cluster-admin` для группы `oidc:admin` | `headlamp-admins.clusterrolebinding.yaml` |
| clientID/clientSecret/issuerURL/scopes | Vault `kv/headlamp/oidc` → `headlamp-oidc.vaultstaticsecret.yaml` |

Claim `role` кладёт action `addRole` в Zitadel: `admin`, если у пользователя
есть одноимённая роль в проекте Homelab, иначе `user`. Роль `admin` выдана
администратору, поэтому cluster-admin получает только он.

В Zitadel тот же action висит на двух триггерах: `POST_AUTHENTICATION` (claim
в профиль, нужен Immich) и `PRE_USERINFO_CREATION` (claim внутрь токена,
нужен Headlamp).

## Файлы

| Файл | Ресурс |
|---|---|
| `vso-headlamp.serviceaccount.yaml` | ServiceAccount для External Secrets Operator |
| `vso-headlamp.vaultauth.yaml` | `VaultAuth` с ролью `headlamp` из Vault |
| `headlamp-oidc.vaultstaticsecret.yaml` | `VaultStaticSecret` `kv/headlamp/oidc` |
| `headlamp-admins.clusterrolebinding.yaml` | `cluster-admin` для группы `oidc:admin` |
| `networkpolicy.yaml` | default-deny ingress + вход из `traefik` |

По одному ресурсу на файл: k8s-валидаторы редактора берут схему первого
документа мультидокументного YAML и ругаются на остальные.

Применение:

```sh
kubectl apply -f platform/headlamp/
```

## Секреты

`client_secret` приложения живёт в Vault (`kv/headlamp/oidc`), оттуда их
доставляет VSO. Ключи: `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`,
`OIDC_ISSUER_URL`, `OIDC_SCOPES`. В Terraform state секрета нет — приложение
создаётся провайдером, значение отдаётся только в консоли Zitadel.

## Диагностика

```sh
kubectl -n headlamp get vaultstaticsecret headlamp-oidc
kubectl -n headlamp get deploy headlamp -o yaml | grep -A3 envFrom
kubectl -n headlamp logs deploy/headlamp --since=5m
```

Claim проверяется на стороне Zitadel, а не кластера: если вход проходит, а
прав нет — дело в роли `admin` у пользователя или в группе из
`ClusterRoleBinding`.

## Применение `k0s.yaml`

`spec.api` не обновляется динамически: после правки `k0s.yaml` нужен
`k0s stop && k0s start`. Секрета в самом `k0s.yaml` нет, реальный issuer
Zitadel подставляет `install.sh` из `values.private.yaml` (untracked, плейсхолдер
в git — `values.private.yaml.example`).
