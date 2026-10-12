# Radar: эксплуатация

## Установка

Все команды — на сервере из корня репозитория, после `git pull --ff-only`.
Сначала Terraform (Zitadel-приложение и роль Vault), затем кластер.

```sh
cd infra/terraform/zitadel && terraform apply
cd ../vault && terraform apply
```

ClientSecret нового приложения в state не попадает — Zitadel отдаёт его только
в консоли. Положить в Vault `kv/radar/oidc` (v2) два ключа:

| Ключ | Откуда | Кто читает |
|---|---|---|
| `client-secret` | clientSecret приложения Radar в Zitadel | `RADAR_OIDC_CLIENT_SECRET` |
| `auth-secret` | случайная строка, например `openssl rand -base64 32` | `RADAR_AUTH_SECRET` |

Имена ключей — дефолты чарта (`auth.existingSecretKey` и
`auth.oidc.clientSecretKey`); задавать их в Application не нужно. Оба секрета
приходят в один Secret `radar-auth`.

`clientID` в Vault не нужен: Radar берёт его из `--auth-oidc-client-id`, то
есть из `valuesObject` в `clusters/casa/platform/radar/app.yaml`. В Helm release он
попадает открытым текстом, но clientID — публичный идентификатор, не секрет;
секретом является только `client-secret`.

`client-secret` и `auth-secret` читаются Radar'ом только при старте, поэтому при
ротации в Vault под пересоздаётся — за это отвечает `rolloutRestartTargets` в
`radar-oidc.vaultstaticsecret.yaml`.

Затем Application и остальное:

```sh
kubectl apply -f clusters/casa/platform/radar/app.yaml

# Дождаться, пока Argo создаст namespace, под и слой RBAC.
kubectl -n radar get pods
argocd app get radar

kubectl apply -f clusters/casa/platform/radar/manifests
```

Порядок важен: namespace `radar` объявлен в `clusters/casa/platform/namespaces/`,
и только после его появления применяются остальные манифесты и маршрут.
Секреты в `radar-auth` должны появиться **до** синка: иначе Radar стартует
без `RADAR_OIDC_CLIENT_SECRET`.

## Проверка

```sh
kubectl -n radar get vaultstaticsecret radar-oidc
kubectl -n radar get pods
kubectl -n radar logs deploy/radar --since=5m | grep -E "\[oidc\]|\[auth\]"
```

В логах при старте ожидаются строки `[oidc] Requesting scopes: [openid profile
email]`, `[oidc] RP-Initiated Logout enabled` и `[oidc] Backchannel Logout
enabled`.

Публичный маршрут без сессии отдаёт `401` (не `302` — вход теперь внутри Radar):

```sh
curl --resolve radar.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://radar.${DOMAIN}/
```

После логина в Zitadel — UI Radar на https://radar.example.com/. Если вход
проходит, а namespace'ов не видно, — не хватает RBAC-привязки: Radar
показывает только то, что пользователю разрешено, и делает это fail-closed.
Проверить глазами:

```sh
kubectl auth can-i list pods -n radar --as=<email> --as-group=oidc:admin
```

Gatus проверяет `http://radar.radar.svc.cluster.local/api/health` из namespace
`monitoring` (правка `clusters/casa/apps/gatus/manifests/config/config.yaml` плюс `kubectl apply -k
clusters/casa/apps/gatus/` сама перезапускает под: ConfigMap с конфигом собирается с хэшем
содержимого). `/api/health` exempt даже при включённой аутентификации.

## Обновление версии

Меняем `targetRevision` (версия чарта) в `clusters/casa/platform/radar/app.yaml`,
применяем `kubectl apply -f clusters/casa/platform/radar/app.yaml` — Argo обновит
релиз сам (self-heal + automated sync). Для отката возвращаем версию в файле и
применяем снова. Перед апгрейдом смотреть release notes:
https://github.com/skyhook-io/radar/releases

## Удаление

```sh
kubectl -n argocd delete application radar
kubectl delete -f clusters/casa/platform/radar/manifests/networkpolicy.yaml
kubectl delete ns radar
```
