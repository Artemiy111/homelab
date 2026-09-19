# Headlamp

RBAC логин-аккаунта (`ServiceAccount headlamp-admin`, `ClusterRoleBinding` и
token) описан в `argocd/applications/headlamp.yaml` через `extraManifests` — отдельного
манифеста здесь больше нет.

# Получить токен

```sh
kubectl -n headlamp get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d
```
