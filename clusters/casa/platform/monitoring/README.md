# monitoring

Базовый NetworkPolicy для всего namespace `monitoring`: `default-deny` на
ingress плюс явные разрешения. Egress не ограничивается.

Юнит владеет namespace `monitoring` и базовым NetworkPolicy для него:
`default-deny` на ingress плюс явные разрешения. Egress не ограничивается.

Namespace объслуживает больше десятка приложений, но правило прежнее: владелец
объявляет свой namespace в своём каталоге, а не отдаёт его потребителям.
Промежуточные middleware Traefik живут отдельно, в `apps/monitoring-middlewares/`.

До появления этого юнита `namespace.yaml` и `networkpolicy.yaml` лежали в
каталоге без `app.yaml`, и root их не видел: файлы были в git, а Argo о них
не знал. NetworkPolicy в кластере существовали, но без меток
`argocd.argoproj.io/instance` — то есть правились руками и не переживали
удаление. Проверено на стенде 2026-10-11.