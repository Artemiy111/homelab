# vmalert: проверки

## После развёртывания

Ожидаемый результат: под vmalert готов, в логах есть сообщение о загруженных
правилах, в Alertmanager видны алерты с `source=vmalert`.

```sh
kubectl -n monitoring get pods -o name | grep vmalert
kubectl -n monitoring get pods -o name | grep vmalert |
  xargs -I{} kubectl -n monitoring logs {} --tail=50 | grep -i 'rule\|alert'
```

Если под не стартует, смотри события CR и пода:

```sh
kubectl -n monitoring describe vmalert vmalert
kubectl -n monitoring get pods -o name | grep vmalert |
  xargs -I{} kubectl -n monitoring describe {}
```

## Проверка потока в Alertmanager

```sh
kubectl -n monitoring exec deploy/alertmanager -- wget -qO- http://localhost:9093/api/v2/alerts 2>/dev/null |
  jq -r '.[] | select(.labels.source == "vmalert") | [.labels.alertname, .status.state] | @tsv'
```

Пустой вывод нормален: правила сработают только при реальном превышении порогов.
Чтобы проверить доставку без ожидания инцидента, отправь тестовый алерт по шагам
из `apps/casa/alertmanager/RUNBOOK.md`.

## Изменение правил

Правила меняются в `VMRule` в Git. Оператор следит за CR и обновляет конфиг
vmalert без ручного рестарта; если под не подхватил правку, перезапусти его:

```sh
kubectl -n monitoring get pods -o name | grep vmalert |
  xargs -I{} kubectl -n monitoring delete {}
```

## Удаление

Удали `Application` и каталог юнита, затем перегенерируй список юнитов Argo.
`VMRule` удалятся вместе с приложением; у vmalert нет PVC, поэтому данных на
диске не остаётся.
