# Bootstrap

Каталог того, что Argo не может применить сам: контроллер не применит
`Application`, который его создаёт. Всё остальное под управлением лежит в
`clusters/casa/`.

| Файл | Что это |
|---|---|
| `root.yaml` | `Application` верхнего уровня: рендерит `clusters/casa/` и создаёт остальные |

Значения чарта Argo живут в его юните — `clusters/casa/platform/argocd/values.yaml`,
и дальше применяются самим Argo.

Разборы подводных камней, версии и диагностика — в
[runbook](../clusters/casa/platform/argocd/RUNBOOK.md). Каталог одноразовый: при переходе на
Flux сносится целиком.

## С нуля до GitOps

Порядок на пустом кластере, где k0s уже установлен и kubeconfig настроен.
Команды выполняются из корня рабочей копии репозитория (macOS).

```sh
git pull

# 1. Сам Argo: контроллер ставится Helm'ом, он не может поставить себя сам.
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --version 10.9.1 \
  --namespace argocd --create-namespace \
  -f clusters/casa/platform/argocd/values.yaml \
  --wait

# 2. Root. Создаёт AppProject'ы, остальные Application'ы и всё под ними.
kubectl apply -f bootstrap/root.yaml
argocd app sync root
```

Дальше Argo управляет собой сам: `platform/argocd/app.yaml` ставит тот же чарт из
git, поэтому настройки меняются коммитом, а не `helm upgrade`. Helm-релиз при этом
«забывают», чтобы он не конкурировал с Argo (RUNBOOK, «Обновление Argo»).

Манифесты Argo читает из публичного зеркала на GitHub
(`https://github.com/Artemiy111/homelab.git`): репозиторий публичный, клон
анонимный по HTTPS, поэтому ни `argocd repo add`, ни deploy key не нужны.

Так сделано из-за цикла: манифесты Forgejo лежат в Forgejo, а Forgejo разворачивает
Argo. На пустом кластере `ssh://git@forgejo…` недостижим, и root не синкается
никогда; зеркало существует до кластера и цикл разрывает. Плата — задержка: Argo
видит состояние зеркала, а не Forgejo. Как переключиться на Forgejo, если нужен
синк ровно с ней, — в [runbook](../clusters/casa/platform/argocd/RUNBOOK.md),
раздел «Бутстрап».

Gateway, `ClusterIssuer` и wildcard-`Certificate` отдельным шагом не ставятся: они
объявлены в юнитах `gateway-api`, `traefik` и `cert-manager` и приезжают первыми
волнами root'а. HTTPS начнёт отвечать, когда cert-manager выпустит сертификат.

Адрес репозитория продублирован в `root.yaml` и во всех юнитах: Argo сопоставляет
репозитории по точному сравнению строки, поэтому смена источника — это массовая
правка одного литерала.

## Проверка

```sh
argocd app list                 # root Synced/Healthy
argocd proj get upstream       # AppProject'ы созданы
argocd app diff root            # пусто
```

Все Application'ы создаются из списка в `clusters/casa/kustomization.yaml`.
Список генерируется: `./scripts/argocd-units.sh > clusters/casa/kustomization.yaml`,
актуальность проверяет `scripts/check.sh`.

## Если Argo сломался

Пока релиз ещё Helm'ов, лечится `helm upgrade` с теми же values и рестартом
`repo-server`: блок `knownHosts` монтируется в под при пересоздании, а не читается
на лету. После адопции (RUNBOOK, «Обновление Argo») релиз забыт, и путь один:
revert коммита в git и `argocd app sync argocd`.

```sh
helm upgrade argocd argo/argo-cd --version 10.9.1 \
  --namespace argocd -f clusters/casa/platform/argocd/values.yaml
kubectl -n argocd rollout restart deploy/argocd-repo-server
```