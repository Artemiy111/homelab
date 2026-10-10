# Bootstrap

Каталог того, что Argo не может применить сам: контроллер не применит
`Application`, который его создаёт. Всё остальное под управлением лежит в
`clusters/casa/`.

| Файл | Что это |
|---|---|
| `root.yaml` | `Application` верхнего уровня: рендерит `clusters/casa/` и создаёт остальные |
| `argocd-values.yaml` | значения чарта Argo CD, только отклонения от дефолтов |

Разборы подводных камней, версии и диагностика — в
[runbook](../docs/runbooks/argocd.md). Каталог одноразовый: при переходе на
Flux сносится целиком.

## С нуля до GitOps

Порядок на пустом кластере, где k0s уже установлен и kubeconfig настроен.

```sh
cd ~/projects/homelab
git pull

# 1. Сам Argo: контроллер ставится Helm'ом, он не может поставить себя сам.
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --version 10.9.1 \
  --namespace argocd --create-namespace \
  -f bootstrap/argocd-values.yaml \
  --wait

# 2. Gateway, issuer и wildcard-сертификат: локальный чарт, Application на
#    него ещё нет (docs/adr/0011, issue #900).
helm template clusters/casa/platform/homelab | kubectl apply -f -

# 3. Репозиторий для Argo: публичный ключ deploy key добавлен в Forgejo
#    (Настройки репозитория → Deploy keys, только чтение), приватный лежит
#    на этой машине.
argocd repo add ssh://git@forgejo.biplane.casa:2222/artemiy/homelab.git \
  --type git --name homelab \
  --ssh-private-key-path ~/.ssh/id_homelab-argocd_homelab-repo

# 4. Root. Создаёт остальные Application'ы и AppProject'ы.
kubectl apply -f bootstrap/root.yaml
argocd app sync root
```

`repoURL` в `root.yaml` и в команде `argocd repo add` должны совпадать
посимвольно: Argo сопоставляет репозитории по точному сравнению строки.

## Проверка

```sh
argocd app list                 # root Synced/Healthy
argocd proj get upstream       # AppProject'ы созданы
argocd app diff root            # пусто
```

Все Application'ы создаются из списка в `clusters/casa/kustomization.yaml`.
Список генерируется: `./scripts/argocd-units.sh > clusters/casa/kustomization.yaml`,
актуальность проверяет `scripts/check.sh`.

## Если Argo не переустанавливается

`helm upgrade` с тем же values, затем рестарт `repo-server` — блок
`knownHosts` монтируется в под, а не читается на лету:

```sh
helm upgrade argocd argo/argo-cd --version 10.9.1 \
  --namespace argocd -f bootstrap/argocd-values.yaml
kubectl -n argocd rollout restart deploy/argocd-repo-server
```