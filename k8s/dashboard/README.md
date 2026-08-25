Добавляем репозиторий и применяем конфиг

```sh
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --create-namespace \
  -f values.yaml

```

Пробрасываем порт из ServiceIP 443 в нормальный 8443 и делаем доступным по localhost:8433
Работает только localhost и только пока не вышли из процесса, используется для временного доступа.
Потом можно сделать ssh тунель и пробросить до localhost своего пк.

```sh
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443

ssh -L 8443:localhost:8443 artlab@192.0.2.10
```

Создаём JWT токен
```sh
kubectl -n kubernetes-dashboard create token dashboard-admin
```