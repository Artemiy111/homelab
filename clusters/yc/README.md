# Кластер `yc`

Доставка для кластера `yc` на Flux. Payload — в `apps/yc/` и `platform/yc/`
(пока пусто); здесь только то, что читает движок.

## Как устроена цепочка

```
коммит в Forgejo → зеркало → GitHub → Flux (только чтение)
```

Forgejo доступен только из локальной сети и кластеру в облаке не виден, поэтому
источник — публичное GitHub-зеркало `https://github.com/Artemiy111/homelab.git`.
Репозиторий публичный, значит `GitRepository` не нужен ни deploy key, ни секрет.

Flux **не пишет в git**: image automation не включаем, версии образов обновляет
Renovate. Коммиты делает человек в Forgejo, кластер лишь применяет результат.

Следствие: изменения появляются в кластере не сразу после merge, а после того,
как зеркало отдаст их на GitHub. Отсюда интервалы в `gotk-sync.yaml`: git
опрашивается раз в 5 минут, применение повторяется раз в 10.

## Что здесь лежит

| Файл | Что это |
| --- | --- |
| `flux-system/gotk-components.yaml` | CRD и контроллеры Flux; сгенерирован `flux install --export`, руками не правится |
| `flux-system/gotk-sync.yaml` | `GitRepository` на GitHub и корневой `Kustomization` с `path: ./clusters/yc` |
| `flux-system/kustomization.yaml` | собирает два файла выше |
| `kustomization.yaml` | список юнитов кластера: один Flux `Kustomization` на приложение или платформенный компонент |
| `platform/envoy-gateway.yaml` | `OCIRepository` и `HelmRelease` Envoy Gateway; `path: ./platform/yc/envoy-gateway/releases` |
| `platform/envoy-gateway-config.yaml` | `GatewayClass`, `EnvoyProxy`, `Gateway`; поднимается после `HelmRelease` |
| `platform/metrics-server.yaml` | `HelmRelease` metrics-server в `kube-system` |
| `apps/test-nginx.yaml` | Flux `Kustomization` тестовой страницы (`path: ./apps/yc/test-nginx/manifests`) |

## Первичная установка

Два шага, потому что CRD должны появиться раньше своих объектов:

```sh
export KUBECONFIG=~/.kube/configs/yc.yaml

kubectl apply -f clusters/yc/flux-system/gotk-components.yaml
kubectl -n flux-system wait --for=condition=Available deploy --all --timeout=5m

kubectl apply -f clusters/yc/flux-system/gotk-sync.yaml
flux -n flux-system get sources git
flux -n flux-system get kustomizations
```

## Как добавить юнит

1. Манифесты — в `apps/yc/<сервис>/manifests/`, со своим `kustomization.yaml`.
2. Flux `Kustomization` — в `clusters/yc/apps/<сервис>.yaml`: один объект на
   приложение, `path` указывает на каталог из шага 1.
3. Ссылку на этот объект — в `clusters/yc/kustomization.yaml` (`resources`).
4. Коммит в Forgejo, дальше зеркало и Flux сделают остальное.

## Проверка

```sh
flux -n flux-system get sources git        # REVISION должен совпасть с GitHub
git ls-remote https://github.com/Artemiy111/homelab.git main
flux -n flux-system get kustomizations     # READY True
kubectl -n flux-system get pods
```

## Чего здесь не делать

- **Не давать Flux право записи в репозиторий.** Оно нужно только image
  automation, а её у нас нет: иначе два агента (Flux и Renovate) правят одни и
  те же манифесты.
- **Не править `gotk-components.yaml` руками** — файл перегенерируется
  `flux install --export` при обновлении Flux.
