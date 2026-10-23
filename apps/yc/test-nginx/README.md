# test-nginx

Тестовая страница: проверка сквозного пути «GitHub → Flux → Gateway → под → внешний балансировщик → браузер». Своей ценности не несёт, состояния не хранит.

## Как устроен доступ

```
клиент :80
  → NLB (статический адрес) → NodePort 30081 на узле
  → Envoy Gateway → HTTPRoute по хосту test-nginx.yc.clusters.biplane.casa
  → Service test-nginx :80 → под :8080
```

Собственного NodePort у приложения нет: наружу торчит только точка входа Gateway. Маршрут выбирается по заголовку `Host`, поэтому на одном Gateway могут висеть разные приложения с разными именами.

Проверять можно по имени (если DNS уже отдаёт адрес балансировщика) или подставив Host вручную:

```sh
curl -s http://test-nginx.yc.clusters.biplane.casa/ | head -3
curl -s -H 'Host: test-nginx.yc.clusters.biplane.casa' http://<ip балансировщика>/ | head -3
```

## Что важно знать

- **DNS-запись заводится в Terraform**, в зоне кластера (`infra/yc/terraform/cluster`): подзона делегирована в Cloud DNS, wildcard'а там нет, поэтому каждое имя добавляется явно.
- **TLS нет.** Gateway слушает только HTTP; сертификат появится вместе с cert-manager и солвером, умеющим писать в Cloud DNS.
- **Образ unprivileged**: работает под UID 101, слушает 8080, root в контейнере не нужен.
- **Namespace не удаляется автоматически** (`prune: disabled`): снятие манифеста уносит Deployment, Service и HTTPRoute, но не namespace. Убирать руками.
