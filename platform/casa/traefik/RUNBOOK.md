# Traefik: эксплуатация

## Маршрут дашборда

Маршрут дашборда Argo не синхронизирует: у Application `traefik` в
`spec.sources` только чарт, каталог `manifests` и `ref: values`, а файла маршрута
там нет. После правки в git применять руками, иначе разойдётся с кластером
(#858):

```sh
kubectl apply -f platform/casa/traefik/manifests/dashboard.route.yaml
```
