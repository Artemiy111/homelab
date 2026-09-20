---
status: accepted
---

# Namespace — граница владения, а не граница среды

Кластер один, а сервисы и заготовки баз CNPG лежат в `default`. Решаем:
namespace разграничивает **владение** — сервис (или платформа) владеет
своим namespace'ом, и CNPG-кластер живёт в namespace своего владельца:
выделенный (один потребитель) — рядом с сервисом, общий (несколько
потребителей) — в нейтральном `databases`. Среды (prod/dev/qa) namespace'ами
не разделяются: namespace не изолирует cluster-scoped ресурсы (CRD, webhook'и,
ClusterRole), общий kernel и узел.

## Considered Options

- **Всё в `default`** (текущее состояние) — нет blast radius, квот и политик;
  одна ошибка `kubectl delete` задевает всех.
- **По слоям: все базы в `databases`** — единообразие, но владение
  расщепляется: «всё про immich» лежит в двух местах, а
  `kubectl delete ns immich` перестаёт уносить базу с собой.
- **По средам** — не работает: CRD и webhook'и оператора, поставленного в dev,
  видны всему кластеру, а узел и kernel общие. Среды разводятся отдельными
  кластерами или машинами, а не namespace'ами.

## Consequences

- `databases` хранит **только** общий кластер `shared`; выделенные кластеры
  (`zitadel`, `immich`, `dawarich`) — в namespace своих сервисов.
- Переезд сервиса в свой namespace дорог и делается инкрементально:
  SealedSecret привязан к namespace и имени и подлежит перешифровке, Ingress и
  TLS-секрет обязаны лежать в namespace сервиса, PVC пересоздаётся.
- Потребители `shared` подключаются cross-namespace
  (`shared-rw.databases.svc`), поэтому пароль нужен в двух namespace — один
  источник правды плюс синхронизация.
- Cross-namespace доступ разрешается явно: Calico NetworkPolicy работает, но
  политик пока нет — включить default-deny до переезда.
- Наблюдаемость и бэкапы не страдают: Barman настраивается на `Cluster`, а
  vmagent ищет по лейблу `cnpg.io/cluster`, а не по namespace.
