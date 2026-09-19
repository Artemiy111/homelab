# sealed-secrets (контроллер в k0s)

| | |
|---|---|
| Чарт | `sealed-secrets/sealed-secrets` 2.20.0 (`https://bitnami-labs.github.io/sealed-secrets-charts`) |
| Контроллер | 0.40.0 (`appVersion`) |
| Namespace | `kube-system` |
| Values | `k8s/sealed-secrets/values.yaml` |
| Клиент | `kubeseal` — пин в `ansible/group_vars/all.yml`, ставит `ansible/host.yml` |

Контроллер расшифровывает `SealedSecret` (`apps/<сервис>/k8s/sealedsecret.yaml`)
в обычные Secret. Приватный ключ расшифровки чартом не управляется: контроллер
создаёт Secret `sealed-secrets-key*`. Его нужно бэкапить — потеря ключа делает
существующие SealedSecret нерасшифровываемыми.

## Установка / обновление

На сервере от `artlab`:

```sh
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets-charts
helm repo update sealed-secrets

helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --version 2.20.0 \
  --namespace kube-system --create-namespace \
  -f k8s/sealed-secrets/values.yaml
```

`--version` фиксирует версию чарта: обновление — это осознанная правка числа
отдельным коммитом. `image.tag` в values не задан, поэтому версия образа
следует за `appVersion` чарта — чарт и приложение двигаются вместе.

`helm upgrade` не обновляет манифесты из `crds/`. Если в новой версии чарта
CRD изменился, применить вручную:

```sh
helm show crds sealed-secrets/sealed-secrets --version 2.20.0 | kubectl apply -f -
```

## Проверка

```sh
kubectl -n kube-system rollout status deploy/sealed-secrets-controller
kubectl -n kube-system get deploy sealed-secrets-controller \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
kubectl -n kube-system get secret | grep sealed-secrets-key
```

Откат: `helm rollback sealed-secrets -n kube-system` и вернуть `--version` назад.

## Версия клиента

`kubeseal_version` в `ansible/group_vars/all.yml` держать равной версии
контроллера (`appVersion` чарта). Обновление клиента — прогон `ansible/host.yml`.
