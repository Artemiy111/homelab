# Traefik Middleware, общие для сервисов в namespace `monitoring`

`oauth2-proxy`, `secure-headers` и `ratelimit-default` объявлялись в
`manifests/` сразу четырёх сервисов: `grafana`, `image-updates`, `netdata` и
`victoria-metrics`. Двенадцать файлов были байт-в-байт идентичны, но под Argo
это нерабочая схема: объект принадлежит ровно одному `Application`, и
`tracking-id` последнего синка забирал его себе. Из-за этого `grafana` и
`victoria-metrics` висели `OutOfSync`, а `image-updates` не мог синхронизироваться
вовсе.

Поэтому три middleware живут здесь, отдельным `Application`, а сервисы
`monitoring` ссылаются на них по имени из своих `HTTPRoute` через `ExtensionRef`
и ничего о middleware не знают.

`homelab-config` живёт здесь по той же причине: namespace `monitoring` делят
двенадцать юнитов, и копия ConfigMap у каждого из пяти потребителей означала бы
`SharedResourceWarning` и драку за объект при `selfHeal`. Объект один,
владелец — этот юнит.

Каталог не сервис: подов здесь нет, только объекты, общие для всего namespace.
`prune: true` — сменить набор безопасно, потребители ссылаются на них по
имени.

Правка любого middleware меняет поведение всех четырёх сервисов сразу: Traefik
перечитывает объекты сам, рестарт не нужен.