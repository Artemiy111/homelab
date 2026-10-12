# Headlamp: эксплуатация

## Применение

```sh
kubectl apply -f clusters/casa/platform/headlamp/
```

## Секреты

`client_secret` приложения живёт в Vault (`kv/headlamp/oidc`), оттуда их
доставляет VSO. Ключи: `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`,
`OIDC_ISSUER_URL`, `OIDC_SCOPES`. В Terraform state секрета нет — приложение
создаётся провайдером, значение отдаётся только в консоли Zitadel.

## Проверка

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
Zitadel и `install.sh` берут его из того же файла. Issuer обязан совпадать
с объявленным в `/.well-known/openid-configuration`, иначе apiserver отклонит
токен: смена домена Zitadel требует правки здесь и рестарта k0s.
