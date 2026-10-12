# node-exporter: эксплуатация

## Проверка

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up{job="node-exporter"}'
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/label/__name__/values?match[]={job="node-exporter"}'
```
