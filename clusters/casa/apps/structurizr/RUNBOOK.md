# Structurizr: эксплуатация

## Сборка и загрузка образа

Готового образа в registry нет, а сервис работает в k8s, поэтому после сборки
образ нужно загрузить в containerd k0s и перезапустить деплоймент:

```sh
docker tag structurizr-structurizr:latest localhost/structurizr:2026.06.28
docker save localhost/structurizr:2026.06.28 \
  | sudo ctr -a /run/k0s/containerd.sock -n k8s.io images import -
kubectl rollout restart deploy/structurizr
```

Тег `localhost/structurizr:<версия>` должен совпадать с `image` в Deployment.

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
