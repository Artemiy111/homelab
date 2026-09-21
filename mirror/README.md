# mirror

Манифест артефактов, которые заранее скачиваются в RustFS (бакет `mirror`) и
отдаются CI анонимно, без обращений в интернет.

- `artifacts.tsv` — строки `<path> <sha256> <url>`: путь объекта в бакете, хэш
  исходника и URL, откуда качать.
- Наполняет CronJob `mirror-sync` (`apps/rustfs`); он же собирает схемы
  kubeconform и открывает бакет на анонимное чтение.
- CI тянет объект как `<mirror>/<path>`, где `<mirror>` —
  `http://rustfs.rustfs.svc.cluster.local:9000/mirror`, и сверяет `sha256`
  скачанного с `artifacts.tsv`.

Добавить артефакт: вычислить `sha256` исходника, дописать строку, применить
ConfigMap `mirror-sync` и запустить Job (команды — в `apps/rustfs/README.md`).
Бакет append-only: чтобы заменить версию, удалить старый объект и
перезапустить.
