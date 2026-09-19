# sealed-secrets (контроллер в k0s)

| | |
|---|---|
| Чарт | `sealed-secrets/sealed-secrets` 2.20.0 (`https://bitnami-labs.github.io/sealed-secrets-charts`) |
| Контроллер | 0.40.0 (`appVersion`) |
| Namespace | `kube-system` |
| Argo Application | `k8s/argocd/sealed-secrets.yaml` |
| Клиент | `kubeseal` — пин в `ansible/group_vars/all.yml`, ставит `ansible/host.yml` |

Контроллер расшифровывает `SealedSecret` (`apps/<сервис>/k8s/sealedsecret.yaml`)
в обычные Secret. Приватный ключ расшифровки чартом не управляется: контроллер
создаёт Secret `sealed-secrets-key*`. Его нужно бэкапить — потеря ключа делает
существующие SealedSecret нерасшифровываемыми.

## Управление

Ставится чартом через Argo CD. Версия чарта — `targetRevision` в
`k8s/argocd/sealed-secrets.yaml`; `image.tag` не задан, поэтому образ следует за
`appVersion` — чарт и приложение двигаются вместе.

Обновление:

```sh
# правится targetRevision в k8s/argocd/sealed-secrets.yaml
kubectl apply -f k8s/argocd/sealed-secrets.yaml
argocd app diff sealed-secrets
argocd app sync sealed-secrets
```

Манифесты из `crds/` Argo не обновляет (`skipCrds`), поэтому CRD применяется
вручную:

```sh
helm show crds sealed-secrets/sealed-secrets --version 2.20.0 | kubectl apply -f -
```

## Проверка

```sh
kubectl -n kube-system rollout status deploy/sealed-secrets-controller
kubectl -n kube-system get secret | grep sealed-secrets-key
```

## Версия клиента

`kubeseal_version` в `ansible/group_vars/all.yml` держать равной версии
контроллера (`appVersion` чарта). Обновление клиента — прогон `ansible/host.yml`.
