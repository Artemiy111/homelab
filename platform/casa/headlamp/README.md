# Headlamp

Вход через OIDC, без service account-токенов. Headlamp сам ходит в Zitadel
и отдаёт apiserver'у `id_token`, который тот проверяет по подписи. Права
выдаёт claim `role` из токена, а не ServiceAccount пода.

Схема по шагам:

| Шаг | Где |
|---|---|
| Приложение OIDC в Zitadel | `infra/casa/terraform/zitadel/applications.tf` |
| Claim `role` (`admin`/`user`) | `infra/casa/terraform/zitadel/actions.tf` |
| Доверие apiserver к Zitadel | `infra/casa/host/etc/k0s/k0s.yaml`, `spec.api.extraArgs` |
| `cluster-admin` для группы `oidc:admin` | `headlamp-admins.clusterrolebinding.yaml` |
| clientID/clientSecret/issuerURL/scopes | Vault `kv/headlamp/oidc` → `headlamp-oidc.vaultstaticsecret.yaml` |

Claim `role` кладёт action `addRole` в Zitadel: `admin`, если у пользователя
есть одноимённая роль в проекте Homelab, иначе `user`. Роль `admin` выдана
администратору, поэтому cluster-admin получает только он.

В Zitadel тот же action висит на двух триггерах: `POST_AUTHENTICATION` (claim
в профиль, нужен Immich) и `PRE_USERINFO_CREATION` (claim внутрь токена,
нужен Headlamp).

По одному ресурсу на файл: k8s-валидаторы редактора берут схему первого
документа мультидокументного YAML и ругаются на остальные.

Применение, состав секретов и диагностика — в `RUNBOOK.md`.
