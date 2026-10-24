# Traefik: эксплуатация

## Маршрут дашборда

Маршрут дашборда Argo не синхронизирует: у Application `traefik` в
`spec.sources` только чарт, каталог `manifests` и `ref: values`, а файла маршрута
там нет. После правки в git применять руками, иначе разойдётся с кластером
(#858):

```sh
kubectl apply -f platform/casa/traefik/manifests/dashboard.route.yaml
```

## Проверка PROXY protocol

Публичный запрос должен попадать на entrypoint `edge` и давать в логе адрес
клиента, а не адрес узла:

```sh
curl -s -o /dev/null -A "peer-check" https://<публичный-хост>/
kubectl -n traefik logs deploy/traefik --since=5m \
  | jq -c 'select(."request_User-Agent"=="peer-check") | {ClientHost,RequestHost}' | tail -1
```

Ожидается адрес клиента. Если там адрес узла — форвардер не отправил
PROXY-заголовок или Secret `casa-edge-target` в `yc` смотрит не на порт `8443`;
проверять конфиг `apps/yc/casa-edge` и логи его пода.
