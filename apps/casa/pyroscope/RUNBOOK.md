# Pyroscope: эксплуатация

## Проверка

```sh
kubectl -n monitoring get pods -l app=pyroscope
kubectl -n monitoring logs -l app=alloy-profiler --tail=20
# в Grafana: Explore → Pyroscope → profiler → процесс
```

## Диагностика

Недозаданный путь выглядит как `permission denied` в `mkdir` и валит весь
процесс, а не только модуль:

```sh
kubectl -n monitoring logs deploy/pyroscope --tail=-1 | grep "module failed"
kubectl -n monitoring get pod -l app=pyroscope
```

`--tail=-1` здесь обязателен: без него `kubectl logs` отдаёт последние 10
строк, а это ровно хвост с ошибкой — кажется, что процесс ничего не писал.
