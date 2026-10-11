# 0009 — 22 Application и 14 namespace пересозданы за две секунды, uptime-kuma потерял базу

Дата: 2026-10-10
Статус: частично устранено, действие открыто
Среда: одноузловой k0s v1.36.3, Argo CD 10.9.1

## Сводка

Синхронизация root в 18:37 UTC сопровождалась массовым удалением и повторным
созданием 22 объектов Application и 14 namespace'ов. Тринадцать namespace'ов
восстановились сами, потому что их содержимое лежит в `manifests/` под Argo.
`uptime-kuma` не восстановился: его MariaDB лежит вне Argo, CR исчез вместе с
namespace, PVC на `longhorn-retain` — вместе с ним. Сервис был недоступен
15,5 часов, данные потеряны.

Что именно удалило объекты, установить не удалось. Это главный незакрытый
вопрос инцидента, и ниже он помечен явно.

## Влияние

- **uptime-kuma недоступен 15,5 часов** — `CrashLoopBackOff`, 169 рестартов.
- **Данные uptime-kuma уцелели и восстановлены.** Их спас StorageClass
  `longhorn-retain` с `reclaimPolicy: Retain`: PVC исчезла вместе с namespace,
  но том `pvc-487052ef-2f48-4bee-a0ec-780aad4e80fd` остался в Longhorn и был
  возвращён вручную — см. разбор восстановления ниже. Первый вывод «данные
  потеряны» был поспешным: он опирался на отсутствие PVC, а не на проверку
  тома. Бэкапов mariadb-operator в кластере действительно нет
  (`physicalbackups` и `backups` пусты), так что уцелел только `Retain`.
- **13 других namespace'ов пострадали формально, не фактически.** Поды
  `ats`, `athens`, `beszel`, `code-server`, `homepage`, `infisical`, `lute`,
  `mermaid-live-editor`, `oauth2-proxy`, `open-webui`, `postgres`, `talk-hpb`,
  `zot` восстановлены при следующем синке и сейчас `Running`. Их данные не
  пострадали только потому, что лежат в PVC, а PVC пересоздались пустыми и
  приложения оказались с пустыми базами — на этот раз это не проявилось, но
  могло.
- **zitadel** пострадал от того же окна, но по другому механизму — см.
  [инцидент 0008](0008-zitadel-secrets-lost-sealedsecret.md).

## Временная шкала

Время UTC.

| Время | Событие |
|---|---|
| 2026-10-10 17:19:29 | Последняя успешная синхронизация root (revision `a849ffe3`) |
| 17:38 | SealedSecret'ы zitadel пересозданы; контроллер sealed-secrets уходит в `giving up` — см. 0008 |
| **18:37:36 — 18:37:38** | **Созданы 22 объекта Application: `athens`, `ats`, `beszel`, `code-server`, `db-exporters`, `gatus`, `grafana`, `homepage`, `node-exporter`, `oauth2-proxy`, `open-webui`, `otel-collector`, `postgres`, `talk-hpb`, `infisical`, `lute`, `mermaid-live-editor`, `monitoring-middlewares`, `uptime-kuma`, `victoria-metrics`, `zitadel`, `zot`** |
| **18:37:37 — 18:37:48** | **Созданы 14 namespace'ов с теми же именами, кроме `db-exporters`, `gatus`, `grafana`, `node-exporter`, `otel-collector`, `monitoring-middlewares`, `victoria-metrics` — они делят `monitoring`** |
| 18:37:38 | root, синхронизация (запись в `status.history`) |
| 18:39:03 — 18:39:10 | root, повторная синхронизация, 0 ресурсов в отчёте — уже ничего не меняла |
| после 18:39 | `uptime-kuma-mariadb` CR отсутствует, PVC отсутствует, под в `CrashLoopBackOff` |
| 2026-10-11 10:13 | Восстановление вручную: `kubectl apply` трёх файлов из `platform/mariadb/`; Grant пересоздан после того, как User появился |
| 2026-10-11 10:20 | Под `uptime-kuma` `Running`, `No user, need setup` — база пуста |
| 2026-10-11 11:00 | Найден том Longhorn `pvc-487052ef-…`: `Released`, `Retain`, отсоединён, 263 МБ, каталог `kuma` на месте, последняя запись 17:38 |
| 11:02 | Очищен `claimRef` у PV, создан PVC `recover-uptime-kuma` с `volumeName` на этот PV, поднят временный `mariadbd` с `--skip-grant-tables` |
| 11:05 | Снят `mariadb-dump` (35 МБ, 66,7 МБ данных), целевая база пересоздана, дамп залит |
| 11:07 | Под перезапущен: `Connected to the database` без `No user, need setup`. В базе 61 монитор, 1 пользователь, 250 773 heartbeat, 854 записи daily |
| 11:08 | Временные PVC и под удалены, том возвращён в `Released`. `uptime-kuma` — `Synced/Healthy`, `kuma.biplane.casa` отдаёт 200 |
| 2026-10-11 11:20 | Данные проверены в интерфейсе, старый том `pvc-487052ef-…` удалён: 243 МБ освобождено, PV ушёл вместе с ним |

## Первопричина

Из установленного:

- **Namespace удаляется каскадом вместе с содержимым.** `platform/mariadb/` не
  под Argo — это осознанное решение, зафиксированное в #902, — и его цена
  проявилась: CR `uptime-kuma-mariadb` исчез и сам не восстановился, потому что
  его никто не применяет.
- **Объекты вне Argo не вернулись, а данные внутри них — да.** PVC пересоздалась
  пустой, но том Longhorn сохранился: StorageClass `longhorn-retain` имеет
  `reclaimPolicy: Retain`. Разница принципиальная — без `Retain` деградация
  была бы необратимой, и никакой `Retain` не заменяет бэкапа: том лежит в том
  же кластере и был найден вручную по счастливой догадке, а не по процедуре.

Не установлено:

- **Что удалило 22 Application и 14 namespace.** Аргументы против Argo: у
  Application на 2026-10-10 нет финализатора `resources-finalizer.argocd.argoproj.io`,
  а без него удаление объекта Application не тянет за собой ресурсы; только
  `longhorn` и `vault-secrets-operator` несут `pre-delete-finalizer`, и их среди
  22 нет. Отчёт операции root за 18:37 перезаписан следующей синхронизацией,
  логи application-controller за окно не сохранились, аудит API-сервера не
  включён (см. #927).
- Почему root счёл эти приложения orphaned, и был ли это prune, каскад или
  ручная команда.

## Что сработало

- Даты создания у Application и namespace — самые дешёвые улики: два поля
  сразу показывают, что произошло массовое пересоздание, а не плановое обновление.
- `uptime-kuma-mariadb` в списке MariaDB CR показал, что оператор жив и
  CRD на месте — то есть дело не в операторе, а в отсутствии объекта.
- Логи mariadb-operator сохранили прямую улику `unable to create new content in
  namespace uptime-kuma because it is being terminated`: момент удаления
  namespace виден в чужом логе, когда в своём ничего нет.

## Уроки

- **Отсутствие PVC не равно потере данных.** Вывод «данных нет» сделан по
  `kubectl get pvc`, который ничего не говорит о томах с `Retain`. Проверять
  надо хранилище: `kubectl get volumes.longhorn.io` показал живой том за
  минуту. Прежде чем писать «потеряно», стоит искать в хранилище.
- **Namespace — это граница прочности, а не просто объект.** Всё вне GitOps
  переживает удаление namespace только если это явно обеспечено: сейчас это
  один StorageClass с `Retain`, а не свойство платформы. Владение namespace'ом
  юнитом — решение с ценой, и оно должно быть явным.
- **Пустой namespace, который вернулся, может выглядеть здоровым.** Тринадцать
  namespace'ов восстановились без потерь только потому, что их данные ещё не
  успели наполниться. На следующий раз тот же сценарий унёс бы их — если бы
  том был на `local-path`, а не на `longhorn-retain`.
- **Восстановление из `Retain`-тома не описано нигде.** Процедура неочевидна:
  PV висит в `Released` со старым `claimRef`, и без ручной правки PV новый PVC
  не привяжется. Это знание стоило отдельного раунда догадок и описано в
  `docs/runbooks/longhorn.md`.

## Действия

| Действие | Issue |
|---|---|
| `FailOnSharedResource=true` и `PruneLast=true` у root | #930 |
| Решить, принадлежат ли namespace'ы юнитам, и если нет — убрать `namespace.yaml` из `manifests/` | #931 |
| Починить приложение, удаляющее namespace при ошибке в prune (#902 убирает ручное применение) | #902 |
| Включить или обоснованно отказаться от аудита API-сервера | #927 |
| Описать возврат тома с `Retain` в runbook Longhorn | #938 |
| Бэкап MariaDB: физические бэкапы вместо надежды на уцелевший том | #937 |