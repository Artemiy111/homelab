# Structurizr: эксплуатация

## Сборка и публикация образа

Образ собирается из исходников и публикуется в Yandex Cloud Registry. Узел —
`amd64`, поэтому сборка только под `linux/amd64`: без `--platform` образ
скачается, но контейнер не запустится.

```sh
docker buildx build --platform linux/amd64 \
  -t registry.yandexcloud.net/<id реестра>/structurizr:2026.06.28 \
  --push clusters/casa/apps/structurizr

docker buildx imagetools inspect \
  registry.yandexcloud.net/<id реестра>/structurizr:2026.06.28 \
  --format '{{json .Manifest.Manifests}}' \
  | jq -r '.[]|"\(.platform.os)/\(.platform.architecture) \(.digest)"'
```

Push идёт учётной записью пользователя: в `~/.docker/config.json` настроен
credential helper `yc` (`yc cloud-registry configure-docker`).

Ожидаемый результат: в выводе push есть `exporting manifest list`, а вторая
команда печатает две строки — `linux/amd64 …` и `unknown/unknown …`.
`unknown/unknown` — attestation-манифест (buildx добавляет provenance), в
`image` идёт **строка `linux/amd64`**: это сам образ, а тег указывает на индекс
из двух манифестов.

Обновление версии: собрать с новым тегом, взять из вывода `linux/amd64`,
обновить `image` в `clusters/casa/apps/structurizr/manifests/deployment.yaml`,
дождаться переката.

```sh
kubectl -n structurizr rollout status deploy/structurizr
kubectl -n structurizr get pod -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
```

В `imageID` должен быть тот же `sha256`, что в манифесте: он доказывает, что
образ скачан из реестра, а не взят из локального хранилища узла.

## Ключ доступа к реестру и его ротация

Реестр приватный, поэтому узел тянет образ с `imagePullSecrets:
structurizr-registry`. Значение — API-ключ сервисного аккаунта
`k8s-image-puller` (роль `cloud-registry.artifacts.puller` на реестр) — лежит в
Vault по пути `kv/yc/cloud-registry`, поле `key`, и доставляется в кластер
`VaultStaticSecret`. В Secret есть только поле `.dockerconfigjson`: сырой ключ в
него не попадает.

У ключа есть срок, поэтому ротация обязательна:

```sh
yc iam api-key create --service-account-name k8s-image-puller \
  --scopes yc.cloud-registry.artifacts.pull --expires-at 8760h --format json \
  | jq -r .secret | vault kv put kv/yc/cloud-registry key=-

kubectl -n structurizr annotate vaultstaticsecret structurizr-registry \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite

kubectl -n structurizr rollout restart deploy/structurizr
kubectl -n structurizr get pod        # ожидаем Ready, без ImagePullBackOff

yc iam api-key list --service-account-name k8s-image-puller   # MASKED KEY старого и нового
yc iam api-key delete <id старого ключа>
```

Проверки без чтения значения:

```sh
vault kv get -field=key kv/yc/cloud-registry | wc -l     # ожидаем 1: ключ, а не JSON вокруг него
kubectl -n structurizr get secret structurizr-registry -o json \
  | jq -r '[.data|keys[]]|join(",")'                     # ожидаем .dockerconfigjson
```

Если под висит в `ImagePullBackOff`, смотреть события пода: `401`/`401
Unauthorized` — истёк или неверен ключ, `403` — у сервисного аккаунта сняли роль
`cloud-registry.artifacts.puller` на реестр.

## Рабочие пространства

Создание нового воркспейса и запоминание его `<id>` выполняется один раз:

1. Открыть `https://structurizr.example.com/workspace/create`
   (встроенной аутентификации нет — воркспейс создаётся сразу).
2. Запомнить `<id>` из URL `/workspace/<id>`.

Публикация (после изменения `homelab.dsl`, локально или на сервере после
`git pull --ff-only`):

```sh
# проверка синтаксиса (Structurizr CLI, тот же парсер, что у сервера)
structurizr validate -workspace structurizr/homelab.dsl

# выгрузить воркспейс на сервер
structurizr push -url https://structurizr.example.com/api \
  -id <id> -workspace structurizr/homelab.dsl
```

CLI скачивается с https://github.com/structurizr/cli (jar) либо запускается в
контейнере `eclipse-temurin:21-alpine`.
