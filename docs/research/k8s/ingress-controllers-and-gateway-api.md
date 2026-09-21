# Ingress-контроллеры и Gateway API: сравнение для homelab на k0s

> Sources: официальные доки и блоги — kubernetes.io (Ingress, Ingress controllers, Gateway API, блог),
> gateway-api.sigs.k8s.io (спецификация, conformance, roles/personas, api-overview), репозиторий
> `kubernetes-sigs/gateway-api` (в т.ч. `conformance/reports`), README проектов
> (`kubernetes/ingress-nginx`, `nginx/nginx-gateway-fabric`, `traefik/traefik`, `envoyproxy/gateway`,
> `istio/istio`, `n42-gateway/n42-gateway`, `Kong/kubernetes-ingress-controller`, `higress-group/higress`,
> `cilium/cilium`, `kgateway-dev/kgateway`, `projectcontour/contour`, `apache/apisix-ingress-controller`,
> `projectcalico/calico`, `metallb/metallb`, `kube-vip/kube-vip`), доки проектов
> (docs.cilium.io, gateway.envoyproxy.io, docs.konghq.com, docs.nginx.com, projectcontour.io,
> docs.tigera.io, metallb.universe.tf, kube-vip.io, doc.traefik.io), CNCF landscape
> (`cncf/landscape`), Kubernetes Blog (retirement 2025-11-11, statement 2026-01-29, externalIPs 2026-05-14,
> Gateway API v1.6 2026-08-03, ingress2gateway 2026-03-20), Datadog Security Labs (2026-02-19);
> данные GitHub REST API на 17.09.2026.

Дата исследования: 2026-09-17. Кластер в репозитории — k0s **v1.36.3+k0s.2** (см. `k8s/k0s/README.md`),
CNI — Calico v3.32.1 (vxlan), kube-proxy в режиме iptables, один узел Fedora Server 44.
Актуальная версия Gateway API — **v1.6.2** (релиз 2026-09-03); ветка v1.6.0 вышла 2026-06-30.

Смежные исследования: [cni-solutions.md](./cni-solutions.md),
[remote-access-metallb-solutions.md](./remote-access-metallb-solutions.md) (MetalLB L2, Tailscale, policy routing),
[k0s-kubernetes-distribution.md](./k0s-kubernetes-distribution.md).

---

## 1. Зачем этот документ / вопрос

Задача — выбрать, на чём строить north-south трафик кластера, и насколько в это вмешивать Gateway API.
Поводом стало то, что **ingress-nginx официально вышел из эксплуатации в марте 2026** (см. раздел 4 и 6.1),
а наш собственный ingress — Traefik — держит адрес через `Service.spec.externalIPs`, устаревающий в Kubernetes 1.36.

Документ отвечает на вопросы:

1. чем Ingress API отличается от Gateway API и зачем переходить;
2. какие контроллеры реально используют в enterprise (с цифрами и первоисточниками);
3. как выглядят проекты по здоровью (GitHub API, релизы, коммиты);
4. кто из них полностью конформен Gateway API;
5. что делать в нашем homelab — с учётом k0s + Calico + MetalLB-ушёл + Tailscale + одного узла.

---

## 2. Ingress API vs Gateway API

### 2.1. Ingress API: что это и в чём ограничение

`Ingress` — исходный «пользовательский» способ направить внешний HTTP/HTTPS-трафик к `Service`. В кластере
обязан работать *ingress controller*, который читает `Ingress` и исполняет его
([Ingress | Kubernetes](https://kubernetes.io/docs/concepts/services-networking/ingress/),
[Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)).
Ключевые ограничения Ingress API:

- **только HTTP/HTTPS**; L4 (TCP/UDP) — вне модели;
- **всё, что сложнее host+path, уехало в аннотации** (`nginx.ingress.kubernetes.io/*`,
  `traefik.ingress.kubernetes.io/*` и т.п.). Аннотации — не типизированный API: их не валидирует
  API-server, их семантика не переносима между контроллерами и меняется от версии к версии;
- **нет ролевой модели**: тот, кто может создать `Ingress`, задаёт конфигурацию общего прокси
  (в т.ч. глобальные куски конфига через snippets). ingress-nginx прямо предупреждает: «Do not use in
  multi-tenant Kubernetes production installations»
  ([README](https://github.com/kubernetes/ingress-nginx#usage-warnings));
- **нет стандартного разделения** между «инфраструктурой» и «приложением».

Аннотации — это по сути `implementation-specific` расширения без схемы. Блог Kubernetes про миграцию
называет их «esoteric annotations, ConfigMaps, and CRDs»
([Ingress2Gateway 1.0](https://kubernetes.io/blog/2026/03/20/ingress2gateway-1-0-release/)).

### 2.2. Gateway API: роли и ресурсная модель

Gateway API — отдельная спецификация Kubernetes SIG Network (API-группа `gateway.networking.k8s.io`,
CRD), развивающая идею Ingress
([API Overview](https://gateway-api.sigs.k8s.io/concepts/api-overview/)). Три ключевых объекта:

| Объект | Что описывает | Область |
|---|---|---|
| **GatewayClass** | класс шлюзов с общей реализацией (аналогия `IngressClass`/`StorageClass`); за ним стоит один контроллер | cluster-scoped |
| **Gateway** | точку входа: адрес, слушатели (`listeners`), протокол, порт, TLS, какие Route к нему можно цеплять | namespaced |
| **Route** (`HTTPRoute`, `GRPCRoute`, `TLSRoute`, `TCPRoute`, `UDPRoute`) | правила «трафик → backend'ы»; цепляются к Gateway через `parentRefs` | namespaced |

Роли и персоны ([Roles and Personas](https://gateway-api.sigs.k8s.io/concepts/roles-and-personas/)):

- **Ian — infrastructure provider** (владелец `GatewayClass`, задаёт реализацию и возможности);
- **Chihiro — cluster operator** (создаёт `Gateway`, управляет политиками, TLS, доступом);
- **Ana — application developer** (создаёт `HTTPRoute` в своём namespace и не трогает общий прокси).

Именно ролевая модель + типизированные поля вместо аннотаций + стандартные L4-маршруты и есть главное,
что Gateway API даёт сверх Ingress. Привязка Route к Gateway защищена `allowedRoutes`, а кросс-namespace
ссылки на `Secret`/`Service` — `ReferenceGrant`.

### 2.3. Что меняется технологически

| Аспект | Ingress API | Gateway API |
|---|---|---|
| Протоколы | HTTP/HTTPS | HTTP, HTTPS, gRPC, TLS, **TCP, UDP** |
| Расширяемость | аннотации, ConfigMap, vendor CRD | типизированные поля, `filters`, policy-attachment, `backendRefs` |
| Типизация/валидация | нет | OpenAPI-схема CRD, валидация API-server |
| Роли/RBAC | все — админы | разделение по персонам и namespace |
| Кросс-namespace | н/д | `allowedRoutes`, `ReferenceGrant` |
| Переносимость | низкая | высокая, подтверждается conformance-тестами |
| Статус L4 TCP/UDP | вне API | `TCPRoute`/`UDPRoute` — **Standard с v1.6** ([блог](https://kubernetes.io/blog/2026/08/03/gateway-api-v1-6-release/)) |

Conformance (раздел 7) — это и есть механизм, который превращает «спецификацию на бумаге» в
гарантию переносимости: контроллер прогоняет набор тестов и публикует отчёт
([Conformance](https://gateway-api.sigs.k8s.io/concepts/conformance/)).

---

## 3. Ландшафт: таблица контроллеров

Легенда Gateway API: ✅ полный (Core + Extended в отчёте v1.6), ⚠️ частичный / только отдельные профили,
❌ не реализует. «Отчёт» — канал, в котором опубликован conformance-report (`standard`/`experimental`).
Ссылки на отчёты — в разделе 7.

| Контроллер | Data plane | Организация / фонд | Лицензия | Ingress API | Gateway API (стандарт) | Gateway API (extended) |
|---|---|---|---|---|---|---|
| **ingress-nginx** | NGINX (C) | k8s SIG Network / CNCF | Apache-2.0 | ✅ | ❌ | ❌ |
| **NGINX Gateway Fabric** | NGINX (Go control plane) | F5/NGINX | Apache-2.0 | — (Gateway API-only) | ✅ | ✅ |
| **Traefik Proxy** | Go (собственный) | Traefik Labs (не CNCF) | MIT | ✅ (Ingress + IngressRoute CRD) | ⚠️ HTTP core partial | ✅ |
| **Envoy Gateway** | Envoy (C++) | Envoy / CNCF graduated | Apache-2.0 | — (Gateway API-only) | ✅ | ✅ |
| **Istio** (ingress/gateway) | Envoy | Istio / CNCF graduated | Apache-2.0 | ⚠️ (legacy Ingress устарел) | ✅ | ✅ |
| **HAProxy Ingress → N42 Gateway** | HAProxy | сообщество (переименован) | Apache-2.0 | ✅ | ✅ (HTTP, отчёт v1.5) | ✅ |
| **Kong** (KIC / Kong Operator) | Kong Gateway (OpenResty/NGINX) | Kong Inc | Apache-2.0 | ✅ | ✅ | ✅ |
| **Higress** | Envoy / Istio-based | Alibaba / CNCF **sandbox** | Apache-2.0 | ✅ | ✅ (только HTTP) | ❌ |
| **Cilium** (Gateway API) | eBPF | Cilium / CNCF **graduated** | Apache-2.0 | ✅ (Cilium Ingress) | ✅ | ✅ |
| **kgateway** (бывш. Gloo OSS) | Envoy | CNCF **sandbox** (дар Solo.io) | Apache-2.0 | ❌ (наследник) | ✅ | ✅ |
| **Contour** | Envoy | CNCF **incubating** | Apache-2.0 | ✅ | ⚠️ нет отчёта v1.5/v1.6 | — |
| **APISIX** (+ ingress controller) | OpenResty/NGINX | Apache Software Foundation | Apache-2.0 | ✅ | ⚠️ нет отчёта в каталоге | — |
| **Calico** | iptables / eBPF | Tigera (не CNCF) | Apache-2.0 | ❌ (в OSS) | ❌ (Ingress Gateway — Enterprise/Cloud) | — |
| **MetalLB** | L4 (ARP/NDP, BGP) | CNCF **sandbox** | Apache-2.0 | — | — | — |
| **kube-vip** | L4 (ARP, BGP) | сообщество | Apache-2.0 | — | — | — |

CNCF-статусы проверены по `cncf/landscape` (`landscape.yml`): Cilium/Istio/Envoy — `graduated`,
Contour/Emissary-Ingress — `incubating`, MetalLB/kgateway/Higress — `sandbox`. Traefik, Kong, APISIX,
Gloo, HAProxy в landscape присутствуют как продукты/проекты **без** поля `project` (не CNCF-проекты).
Calico развивает компания Tigera, «Ingress Gateway based on K8s Gateway API» в её матрице — функция
Calico Enterprise/Cloud, а не OSS ([docs.tigera.io/about](https://docs.tigera.io/calico/latest/about/)).

---

## 4. Популярность в enterprise

### 4.1. Главная цифра: ingress-nginx ≈ 50% cloud-native окружений

Первоисточник — совместное заявление Kubernetes Steering Committee и Security Response Committee
([Ingress NGINX: Statement…, 2026-01-29](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)):

> «**Ingress NGINX, a piece of critical infrastructure for about half of cloud native environments**…»
> «According to **internal Datadog research, about 50% of cloud native environments** currently rely on this tool».

То есть оценка ~50% — это **телеметрия Datadog**, пересказанная в заявлении Kubernetes. Datadog Security
Labs подтверждает: «The Kubernetes statement estimates that about 50% of cloud native environments rely on
Ingress NGINX, a figure drawn from Datadog's telemetry data»
([Datadog Security Labs, 2026-02-19](https://securitylabs.datadoghq.com/articles/kubernetes-ingress-nginx-retirement-warning/)).

### 4.2. Чего в первоисточниках нет

- **CNCF Annual Survey 2024 не разбивает респондентов по ingress-контроллерам.** Я скачал PDF отчёта
  ([cncf_annual_survey24](https://www.cncf.io/wp-content/uploads/2025/04/cncf_annual_survey24_031225a.pdf),
  опубликован 2025-04-01, 750 респондентов) и проверил текст: отдельного вопроса про ingress controller
  там нет; есть Service Mesh и список используемых CNCF-проектов (в нём один раз упоминается
  *Emissary Ingress*). Опубликованного CNCF Annual Survey 2025 на дату исследования нет
  (самый свежий — [CNCF Annual Report 2025](https://www.cncf.io/reports/cncf-annual-report-2025/), февраль 2026,
  но это отчёт организации, а не опрос пользователей).
- **Публичного Datadog-отчёта с пофреймворковой разбивкой ingress-контроллеров найти не удалось.**
  Единственная найденная первичная цифра Datadog — те самые ~50% для ingress-nginx, приведённые в
  заявлении Kubernetes. Гранулярных процентов «Traefik / Envoy / HAProxy / прочее» из first-party
  телеметрии в открытом доступе нет — это **явный пробел данных**, а не «ноль».

### 4.3. Практический (не проценты) вывод о том, чем заменяют

Заявление Kubernetes и блог про ingress2gateway прямо рекомендуют **Gateway API**. Куда идут вендоры
и платформы, видно по first-party фактам:

- **Envoy** стал общим data plane для большинства современных gateway'ев (Envoy Gateway, Istio, Gloo/kgateway,
  Contour, Higress) — это следует из состава conformance-отчётов и README проектов (разделы 6–7).
- **Managed-платформы** двигают собственные реализации: GKE Gateway (отчёт `gke-gateway`), AWS Load
  Balancer Controller (отчёт `aws-load-balancer-controller`) — см. каталог
  [`conformance/reports`](https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports).
- **CNCF-статус** как маркер «долгоживущего» выбора: graduated — Cilium, Istio, Envoy; incubating — Contour,
  Emissary; sandbox — MetalLB, kgateway, Higress.

Вывод для homelab: отраслевой вектор — Gateway API; ingress-nginx «по умолчанию» уходит, и это уже
свершившийся факт (раздел 6.1).

---

## 5. Популярность и здоровье проектов на GitHub

Числа собраны через GitHub REST API (`gh api`) **17.09.2026** (звёзды, форки, открытые issues,
контрибьюторы, дата последнего релиза и push). «Коммитов/90д» — число коммитов в default branch за
период с 2026-06-17 по 2026-09-17 включительно. Контрибьюторы считаны с `?anon=true`, поэтому цифра
включает анонимных авторов.

| Репозиторий | ⭐ | Форки | Open issues | Контрибьюторы | Последний релиз | Коммитов/90д | Лицензия |
|---|---:|---:|---:|---:|---|---:|---|
| `traefik/traefik` | 64 880 | 6 200 | 940 | 1 121 | v3.7.13 (2026-09-04) | 261 | MIT |
| `Kong/kong` | 44 147 | 5 210 | 200 | 452 | 3.9.3 (2026-06-17) | — | Apache-2.0 |
| `istio/istio` | 38 395 | 8 375 | 503 | 1 465 | 1.31.0 (2026-08-31) | 316 | Apache-2.0 |
| `cilium/cilium` | 25 229 | 4 071 | 1 089 | 1 419 | v1.20.2 (2026-09-16) | **1 626** | Apache-2.0 |
| `kubernetes/ingress-nginx` | 19 467 | 8 562 | 348 | 1 215 | controller-v1.15.1 (2026-03-19) | **0** | Apache-2.0 |
| `apache/apisix` | 17 135 | 2 946 | 251 | 519 | 3.18.0 (2026-08-20) | — | Apache-2.0 |
| `higress-group/higress` | 9 397 | 1 304 | 1 114 | 201 | v2.2.4 (2026-08-13) | 163 | Apache-2.0 |
| `metallb/metallb` | 8 353 | 1 077 | 98 | — | metallb-chart-0.16.1 (2026-05-27) | — | Apache-2.0 |
| `projectcalico/calico` | 7 358 | 1 606 | 278 | 871 | v3.32.2 (2026-08-30) | **1 385** | Apache-2.0 |
| `kgateway-dev/kgateway` | 5 688 | 810 | 229 | — | v2.4.5 (2026-09-16) | 180 | Apache-2.0 |
| `nginx/kubernetes-ingress` (F5 NGINX IC) | 5 078 | 2 050 | 245 | 193 | v5.6.3 (2026-09-16) | 282 | Apache-2.0 |
| `emissary-ingress/emissary` | 4 523 | 708 | 404 | 260 | v4.1.0 (2026-05-19) | 88 | Apache-2.0 |
| `projectcontour/contour` | 3 948 | 728 | 122 | 245 | v1.33.7 (2026-09-07) | 79 | Apache-2.0 |
| `envoyproxy/gateway` | 3 036 | 867 | 760 | 418 | v1.9.1 (2026-08-28) | 366 | Apache-2.0 |
| `kubernetes-sigs/gateway-api` | 2 997 | 789 | 224 | 381 | v1.6.2 (2026-09-03) | 140 | Apache-2.0 |
| `kube-vip/kube-vip` | 2 957 | 320 | 78 | — | v1.2.4 (2026-09-16) | — | Apache-2.0 |
| `Kong/kubernetes-ingress-controller` | 2 412 | 624 | 284 | 139 | v3.5.13 (2026-08-07) | 35 | Apache-2.0 |
| `nginx/nginx-gateway-fabric` | 1 165 | 219 | 98 | 90 | v2.7.2 (2026-09-16) | 312 | Apache-2.0 |
| `n42-gateway/n42-gateway` (бывш. HAProxy Ingress) | 1 168 | 293 | 82 | 90 | v0.16.1 (2026-05-04) | 40 | Apache-2.0 |
| `apache/apisix-ingress-controller` | 1 144 | 390 | 55 | 152 | 2.2.0 (2026-08-18) | 46 | Apache-2.0 |
| `solo-io/gloo` (OSS, EOL) | 169 | 12 | 1 877 | — | v1.22.3 (2026-08-27) | — | Apache-2.0 |

Наблюдения по здоровью:

- **ingress-nginx** — архив: `archived=true`, последний push 2026-03-23, последний релиз controller-v1.15.1
  (2026-03-19), **0 коммитов за 90 дней**. 19 467 звёзд и 8 562 форка — это «памятник», а не живой проект.
  Helm-чарты и образы остаются доступны, но обновлений безопасности больше не будет
  ([README](https://github.com/kubernetes/ingress-nginx), [блог 2025-11-11](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)).
- **HAProxy Ingress переименован в N42 Gateway.** GitHub-редирект `jcmoraisjr/haproxy-ingress` ведёт на
  [`n42-gateway/n42-gateway`](https://github.com/n42-gateway/n42-gateway); в README — прежнее описание
  «Ingress and Gateway API controller implementation for HAProxy». Релизная линия — `v0.16.x`/`v0.17-alpha`,
  т.е. проект жив, но это по-прежнему «0.x alpha/beta»-продукт с малой командой.
- **Gloo OSS мёртв как отдельный проект:** README [`solo-io/gloo`](https://github.com/solo-io/gloo) объявляет
  **End of Life 31.12.2026**, а код в конце 2024 был подарен CNCF и переименован в **kgateway**. Обратите
  внимание на аномалию метрик: у `solo-io/gloo` всего 169 звёзд и дата создания 2024-11-07 — GitHub-звёзды
  не переехали в новый репозиторий; «настоящий» kgateway — это
  [`kgateway-dev/kgateway`](https://github.com/kgateway-dev/kgateway) (5 688 ⭐).
- **Envoy Gateway** при 3 036 звёздах имеет очень активный конвейер (366 коммитов/90д) и 760 открытых issues —
  проект молодой и быстро развивается.
- **NGINX Gateway Fabric** — официальная Gateway API-линейка F5/NGINX, отдельная от `nginx/kubernetes-ingress`
  (классический NGINX Ingress Controller, 5 078 ⭐). Блог Kubernetes предупреждает не путать
  ingress-nginx (community, retired) и NGINX Ingress (F5)
  ([Before You Migrate, 2026-02-27](https://kubernetes.io/blog/2026/02/27/ingress-nginx-before-you-migrate/)).

---

## 6. Подробные отличия по контроллерам

Ниже — по каждому значимому проекту: data plane, сильные/слабые стороны, операционная сложность.
Ресурсный след (CPU/RAM) вендоры публикуют редко; там, где первичных цифр нет, это отмечено явно.

### 6.1. ingress-nginx (retired)

- **Data plane:** NGINX (C). **Завершён:** best-effort поддержка до марта 2026, затем никаких релизов,
  багфиксов и патчей безопасности; репозитории переведены в read-only и перенесены в `kubernetes-retired`
  ([README](https://github.com/kubernetes/ingress-nginx), [retirement-блог](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)).
- **Причины:** 1–2 мейнтейнера «по выходным», технический долг, а snippets-аннотации превратились из фичи
  в класс уязвимостей. Проект-замена InGate так и не созрел и тоже закрыт.
- **Безопасность как мотив:** CVE-2025-1974 (IngressNightmare, CVSS 9.8) и ещё четыре HIGH CVE в феврале
  2026 ([Datadog Security Labs](https://securitylabs.datadoghq.com/articles/kubernetes-ingress-nginx-retirement-warning/)).
- **Gateway API:** не поддерживает (нет отчёта conformance).
- **Вывод:** в новых кластерах не разворачивать; в текущих — только как временный компонент до миграции.

### 6.2. NGINX Gateway Fabric (F5/NGINX)

- **Data plane:** NGINX, control plane на Go. **Лицензия** Apache-2.0, репозиторий `nginx/nginx-gateway-fabric`.
- **Gateway API:** официальная таблица совместимости — `GatewayClass`/`Gateway`/`HTTPRoute`/`GRPCRoute`/
  `ReferenceGrant`/`TLSRoute` Core ✅; `Gateway` Extended — partial; `TCPRoute`/`UDPRoute` Extended ✅;
  `BackendTLSPolicy` Core partial / Extended ✅ ([Gateway API compatibility](https://docs.nginx.com/nginx-gateway-fabric/overview/gateway-api-compatibility/)).
- **Фичи:** mTLS на фронте и бэкенде, OIDC/JWT/basic auth, WAF (F5 WAF for NGINX), Request Mirroring,
  session persistence, rate-limit policy (часть — через NGINX Plus). Часть продвинутого — коммерческая.
- **Сложность:** средняя; отдельная линия от NGINX Ingress Controller (F5), миграция между ними —
  документированная, но не автоматическая.

### 6.3. Traefik Proxy (текущий ingress homelab)

- **Data plane:** собственный Go-прокси (не NGINX/Envoy). **Лицензия** MIT, репозиторий `traefik/traefik`.
- **Ingress API:** ✅; плюс собственные CRD `IngressRoute`/`IngressRouteTCP`/`IngressRouteUDP` и
  `Middleware`/`ServersTransport`/`TLSStore`. Именно так устроена папка `k8s/traefik/` в этом репозитории.
- **Gateway API:** есть провайдер (`kubernetesGateway`), но по собственному отчёту v3.7.10 профиль
  **HTTP: Core = partial** (пропущен тест `HTTPRouteMultipleGateways`), Extended = success; GRPC/TLS — Core success
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/traefik-traefik/experimental-v3.7.10-default-report.yaml)).
- **ACME:** встроенный ACME-клиент (Let's Encrypt, в т.ч. HTTP-01/TLS-ALPN/DNS-01); TLSStore/defaultCertificate.
  В нашем Docker-стенде ACME уже настроен ([apps/traefik/traefik.tpl.yaml](../../../apps/traefik/traefik.tpl.yaml)).
- **Фичи:** middleware-цепочки (headers, forwardAuth, rateLimit, redirect, stripPrefix), балансировка,
  TCP/UDP, WebSocket/HTTP2/gRPC, метрики Prometheus (включены в `k8s/traefik/values.yaml`).
- **Слабые стороны:** Gateway API-поддержка неполная (HTTP Core partial); нет WAF из коробки; MIT и вне CNCF —
  governance зависит от одной компании (Traefik Labs).
- **Ресурсный след:** небольшой (один Go-бинарник), но точных первичных цифр для нашего профиля нет — **не измерялось**.

### 6.4. Envoy Gateway

- **Data plane:** Envoy. **Control plane:** Go. Лицензия Apache-2.0, проект под зонтиком Envoy (CNCF graduated).
- **Gateway API:** core+extended success по HTTP/TLS/GRPC в отчёте v1.6 (канал experimental)
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/envoy-gateway/experimental-v1.9.0-default-report.yaml)).
- **Фичи:** нативный Gateway API, ext_authz/ext_proc, rate limiting, JWT, oauth2/OIDC (через SecurityPolicy),
  WebSocket/HTTP2/gRPC, TCP/UDP, Backend TLS, AI/Inference Extension. WAF — через Coraza/Wasm или внешний.
- **Плюсы:** «эталонная» реализация Gateway API на самом распространённом data plane; активная разработка;
  бэкенд, который умеют все облака.
- **Минусы/сложность:** Envoy-модель (listeners/clusters/routes) тяжелее для понимания, чем Traefik;
  нет встроенного ACME — сертификаты обычно через cert-manager; на 1 узле это ещё один control plane.
- **Ресурсный след:** публичных «официальных» цифр нет; по опыту требует больше RAM, чем Traefik — **не измерялось**.

### 6.5. Istio (ingress/gateway)

- **Data plane:** Envoy (sidecar и/или ambient). CNCF graduated, Apache-2.0.
- **Gateway API:** core+extended success по HTTP/GRPC/TCP/TLS + MESH-HTTP
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/istio-istio/1.31.0-default-report.yaml)).
- **Фичи:** mTLS, service mesh, rich traffic management, observability (Kiali/Prometheus/Jaeger).
- **Вывод для homelab:** функционально избыточен; зато «резюме-ценный» для enterprise. Istio Ingress —
  legacy, современный путь — Gateway API.

### 6.6. HAProxy Ingress → N42 Gateway

- **Data plane:** HAProxy. Лицензия Apache-2.0. Проект переименован, репозиторий `n42-gateway/n42-gateway`.
- **Gateway API:** отчёт v1.5 (канал experimental), GATEWAY-HTTP Core + Extended success (35 extended-фич)
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.5/haproxy-ingress/experimental-v0.17.0-alpha.1-default-report.yaml)).
- **Плюсы:** HAProxy — зрелый, быстрый L4/L7; низкий ресурсный след.
- **Минусы:** версии `0.x` (alpha/beta), небольшая команда (40 коммитов/90д), переименование создаёт
  путаницу в документации и миграциях.

### 6.7. Kong (KIC / Kong Operator)

- **Data plane:** Kong Gateway (OpenResty/NGINX + Lua). Kong Inc, Apache-2.0 (OSS).
- **Gateway API:** `kong-operator` отчёт — core+extended success по HTTP/GRPC/TCP/TLS/UDP (вариант
  `traditional_compatible`)
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/kong-operator/experimental-v2.3.1-traditional_compatible-standard-report.yaml)).
  Gateway API reconciliation в KIC включается, только если CRD установлены **до** старта контроллера
  ([Kong Gateway API](https://docs.konghq.com/kubernetes-ingress-controller/latest/concepts/gateway-api/)).
- **Фичи:** огромная библиотека плагинов (auth, rate-limit, transform, observability); WAF и часть плагинов —
  enterprise.
- **Сложность:** высокая: Kong Gateway + DB/DB-less + оператор/KIC; много движущихся частей. Для homelab — избыточно.

### 6.8. Higress

- **Data plane:** Envoy + Istio-based control plane. Alibaba, Apache-2.0, CNCF sandbox.
- **Gateway API:** отчёт standard, но только профиль **GATEWAY-HTTP**, Core success, Extended не заявлен
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/higress-group-higress/standard-v2.2.4-default-report.yaml)).
- **Фичи:** встроенный WAF (ModSecurity/Coraza), AI-gateway, WASM-плагины, консоль.
- **Минусы:** документация и сообщество в основном китайские; 1 114 открытых issues — высокий «хвост».
  Для homelab — нет смысла.

### 6.9. Cilium (Gateway API)

- **Data plane:** eBPF. CNCF graduated, Apache-2.0.
- **Gateway API:** **standard-channel** отчёт — core+extended success по HTTP/GRPC/TCP/TLS/UDP + MESH
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/cilium/standard-v1.20.0-default-report.yaml)).
  Плюс Cilium может сам выдавать LoadBalancer-IP (LB IPAM) и анонсировать их (BGP/L2) — то есть заменить
  MetalLB. В нашем кластере это означало бы смену CNI Calico → Cilium, а в k0s смена CNI = пересоздание
  кластера ([cni-solutions.md](./cni-solutions.md#71-главное-правило-cni-выбирается-при-создании-кластера)).
- **Вывод:** самый мощный вариант архитектурно, но самый дорогой по перестройке; отложить.

### 6.10. kgateway (бывш. Gloo OSS)

- **Data plane:** Envoy. CNCF sandbox (подарен Solo.io в конце 2024), Apache-2.0.
- **Gateway API:** core+extended success по HTTP/GRPC/TCP/TLS
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/kgateway/v2.4.0-rc.1-report.yaml)).
- **Важно:** Gloo OSS **EOL 31.12.2026**; мигрировать надо на kgateway
  ([README solo-io/gloo](https://github.com/solo-io/gloo)).

### 6.11. Contour

- **Data plane:** Envoy. CNCF incubating, Apache-2.0.
- **Gateway API:** Ingress ✅ и Gateway API ✅ исторически, но в каталоге `conformance/reports` v1.5/v1.6
  отчётов Contour **нет** — значит актуальный уровень conformance из первоисточника не подтверждён
  на дату исследования (это **пробел данных**). Активность умеренная (79 коммитов/90д), релизы регулярные.

### 6.12. Apache APISIX (+ APISIX Ingress Controller)

- **Data plane:** APISIX (OpenResty/NGINX + etcd). Apache Software Foundation, Apache-2.0.
- **Gateway API:** в каталоге conformance-отчётов APISIX **отсутствует**; поддержка Gateway API заявлена
  в документации ingress-controller, но подтверждённого отчёта нет — **не проверено по первоисточнику**.
- **Фичи:** плагинный движок (rate-limit, auth, WAF-плагины), etcd-конфиг.
- **Сложность:** высокая (Ingress Controller + APISIX + etcd).

### 6.13. Calico

- **Data plane:** iptables/eBPF — это **CNI**, а не L7-gateway. В OSS нет своей реализации Gateway API;
  «Ingress Gateway based on K8s Gateway API» — функция Calico Enterprise/Cloud
  ([docs.tigera.io/about](https://docs.tigera.io/calico/latest/about/)). В таблице контроллеров Calico
  присутствует для полноты: как ingress-контроллер в OSS он не рассматривается.

### 6.14. MetalLB / kube-vip — только L4 (контраст)

- **MetalLB** выдаёт Service `type: LoadBalancer` IP из пула; в L2-режиме отвечает на ARP (IPv4)/NDP (IPv6),
  и **весь трафик на IP идёт на один узел** — «layer 2 does not implement a load balancer»
  ([MetalLB L2](https://metallb.universe.tf/concepts/layer2/)). BGP-режим анонсирует маршруты.
- **kube-vip** делает то же (ARP/BGP) плюс VIP control plane ([kube-vip](https://kube-vip.io/)).
- **Ключевое:** это L4-слой адресации, ортогональный L7-маршрутизации. Gateway API-контроллер *нуждается*
  в способе получить внешний адрес: либо `Service type: LoadBalancer` (MetalLB/kube-vip), либо
  `hostNetwork`/NodePort, либо LB-IPAM самой CNI (Cilium). В нашем кластере MetalLB удалён, а Traefik
  держит адрес через `externalIPs` — см. раздел 8.

---

## 7. Gateway API: conformance по контроллерам

### 7.1. Что такое conformance

Conformance — это набор тестов из репозитория Gateway API, которые проверяют реальное поведение
контроллера, а не YAML. Три понятия ([Conformance](https://gateway-api.sigs.k8s.io/concepts/conformance/)):

1. **Release channels:** `standard` (beta+ поле) и `experimental` (standard + экспериментальное, может
   ломаться/исчезать). С v1.6 экспериментальные API выделены в группу `gateway.networking.x-k8s.io` с
   префиксом `X` ([блог v1.6](https://kubernetes.io/blog/2026/08/03/gateway-api-v1-6-release/)).
2. **Support levels:** **Core** (переносимые, ожидаются у всех), **Extended** (переносимые, но не у всех),
   **Implementation-specific** (вендорские, вне тестов).
3. **Conformance tests** → публикуемый `ConformanceReport` со статистикой и `supportedFeatures`.

Отчёты лежат в [`kubernetes-sigs/gateway-api/conformance/reports/<version>/<impl>/`](https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports);
каталог решений — на [gateway-api.sigs.k8s.io/implementations](https://gateway-api.sigs.k8s.io/implementations/).

### 7.2. Conformance-статус (по отчётам v1.6 / v1.5)

| Реализация | Отчёт (версия) | Канал | HTTP | GRPC | TLS | TCP | UDP | MESH |
|---|---|---|---|---|---|---|---|---|
| **Cilium** | standard v1.20.0 | standard | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | ✅ MESH-HTTP/GRPC |
| **Envoy Gateway** | experimental v1.9.0 | experimental | ✅ C+E | ✅ C+E | ✅ C+E | — | — | — |
| **Istio** | v1.31.0 | experimental | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | — | ✅ MESH-HTTP |
| **kgateway** | v2.4.0-rc.1 | experimental | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | — | — |
| **Kong Operator** | v2.3.1 (traditional) | experimental | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | — |
| **NGINX Gateway Fabric** | v2.7.0 | experimental | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | ✅ C+E | — |
| **N42 (HAProxy Ingress)** | v0.17.0-alpha.1 | experimental | ✅ C+E (v1.5) | — | — | — | — | — |
| **Higress** | v2.2.4 | standard | ✅ **Core only** | — | — | — | — | — |
| **Traefik** | v3.7.10 | experimental | ⚠️ **Core partial**, Extended ✅ | ✅ Core | ✅ C+E | — | — | — |
| **Contour** | нет отчёта v1.5/v1.6 | — | — | — | — | — | — | — |
| **APISIX** | нет отчёта | — | — | — | — | — | — | — |
| **ingress-nginx** | нет (retired) | — | — | — | — | — | — | — |

Обозначения: C — Core, E — Extended; «—» — в отчёте профиль не заявлен. У Traefik HTTP `core=partial`
из-за пропущенного теста `HTTPRouteMultipleGateways` (см. отчёт).

Практический вывод: **полностью конформен на стандартном канале сейчас Cilium**; большинство остальных
подтверждают core+extended в экспериментальном канале (это нормально — контроллеры тестируют experimental
API, который является надмножеством). Traefik — единственный из популярных, у кого Core HTTP неполный.

---

## 8. Что стоит в homelab сейчас и варианты миграции

### 8.1. Фактическое состояние (проверено по репозиторию)

| Компонент | Факт | Источник |
|---|---|---|
| Кластер | k0s **v1.36.3+k0s.2**, один узел Fedora Server 44 | `k8s/k0s/README.md:9` |
| CNI | **Calico v3.32.1, vxlan**, kube-proxy iptables | `k8s/k0s/k0s.yaml` |
| Ingress | **Traefik**, Helm chart 41.4.0, единственный ingressClass `traefik` (default) | `k8s/traefik/values.yaml` |
| Адрес входа | `Service type: ClusterIP` + **`externalIPs: [<node1-ip>]`** | `k8s/traefik/values.yaml:13-15` |
| MetalLB | **удалён** («на одном узле не нужен — kube-proxy externalIPs достаточно») | `k8s/traefik/values.yaml:12`, `k8s/k0s/README.md:159-173` |
| Маршруты | 48 файлов `*.ingress.yaml` (Ingress) + `*.ingressroute.yaml` (Traefik CRD) + middleware | `k8s/traefik/` |
| TLS | секрет **`wildcard-tls`** (`*.example.com`, Let's Encrypt) на всех маршрутах | ссылки в `k8s/traefik/*` |
| DNS | Technitium, wildcard `*.example.com` → `<node1-ip>` | `README.md`, `apps/technitium/` |
| Tailscale | на хосте, subnet route `<node1-lan-cidr>` + split DNS; доступ из tailnet починен policy-routing правилом | `apps/tailscale/README.md`, `remote-access-metallb-solutions.md` |

**Важная поправка к «известному контексту» задачи:** MetalLB (в т.ч. пул `<metallb-ip>/32`) в кластере
**больше нет** — он удалён 2026-09-15, VIP `<node1-vip>` не используется, вход идёт на `<node1-ip>` через `externalIPs`.
Заметки в `remote-access-metallb-solutions.md` описывают более раннее состояние (`<node1-vip>` + MetalLB) и в этой
части устарели относительно `README.md` и манифестов.

### 8.2. Две проблемы, которые надо решить в любом случае

1. **`Service.spec.externalIPs` устарел в Kubernetes 1.36** — а у нас ровно 1.36.3. Поле формально
   deprecated; ожидается, что будущий минорный релиз **уберёт поддержку из kube-proxy** и потребует от
   conformant-реализаций *не* поддерживать его. Первоисточник:
   [Kubernetes v1.36: Deprecation and removal of Service ExternalIPs](https://kubernetes.io/blog/2026/05/14/deprecation-of-service-externalips/)
   (2026-05-14). Причина — CVE-2020-8554: `externalIPs` позволяет «угнать» чужой IP, т.к. API предполагает
   полностью доверенных пользователей. Рекомендуемая замена в блоге — **`type: LoadBalancer` через
   не-облачный LB-контроллер, например MetalLB**. Это прямо возвращает нас к удалённому MetalLB.
2. **Gateway API — не «дроп-ин» для Ingress.** Все маршруты в `k8s/traefik/` придётся перевести
   (часть — автоматически: `ingress2gateway`), а `IngressRoute`, `Middleware`, `ServersTransport`,
   `TLSStore` — это Traefik-специфичные CRD, для которых аналог в Gateway API другой.

### 8.3. Варианты

| Вариант | Плюсы | Минусы | Итог |
|---|---|---|---|
| **A. Оставить как есть (Traefik + externalIPs)** | 0 работы | `externalIPs` deprecated; безопасности нет (CVE-2020-8554 класс) | ❌ не рекомендуется |
| **B. Traefik + вернуть MetalLB L2, остаться на Ingress/IngressRoute, включить Gateway API-провайдер Traefik** | Минимум изменений; отдаём `<node1-ip>`/`<node1-vip>` законно; ACME и TLS уже работают; можно постепенно переводить маршруты | HTTP Core partial; Gateway API-скилл ограничен; Governance/лицензия вне CNCF | ✅ базовый рабочий путь |
| **C. Traefik для старых маршрутов + Envoy Gateway как Gateway API-реализация + MetalLB L2** | Полный conformance (core+extended); Envoy — индустриальный data plane; чистый Gateway API-скилл; отраслевой вектор | +1 control plane/data plane на одноузловом кластере; ACME через cert-manager; нужен отдельный адрес/порт | ✅ **рекомендуемый целевой** |
| **D. NGINX Gateway Fabric + MetalLB L2** | Полный conformance; NGINX-скилл; проще, чем Envoy-модель | Та же история с cert-manager; F5-специфичные политики; ещё один прокси рядом с Traefik | Альтернатива C |
| **E. Cilium Gateway API (заменить Calico)** | Самый мощный: eBPF, LB-IPAM, BGP/L2, full conformance | Смена CNI в k0s = пересоздание кластера; большой объём работ | Отложить |
| **F. Istio / Kong / Higress / APISIX / kgateway** | Много фич | Сильно избыточно для homelab; каждая — отдельный «зоопарк» | ❌ |

### 8.4. Что делать с текущим reverse proxy

**Traefik не выбрасывать.** Это рабочий, живой и умеющий ACME компонент, на котором уже висят 48 маршрутов.
Правильная тактика:

1. **Сразу** убрать зависимость от `externalIPs`: вернуть MetalLB (L2) и сделать Traefik
   `Service type: LoadBalancer` с фиксированным IP из пула. Это закрывает deprecated-API и сохраняет
   `wildcard-tls` и все ингрессы без правок.
2. **Параллельно** поднять выбранный Gateway API-контроллер (вариант C/D) на отдельном хосте/порту или
   на отдельном адресе и перевести на него **новые** маршруты, начиная с одного сервиса
   (например, `home.example.com`).
3. Старые `Ingress` переводить через `ingress2gateway` (поддерживает >30 ingress-nginx-аннотаций; для
   Traefik-аннотаций применимость ограничена — часть переписывается в `HTTPRoute`/`Middleware`).
4. После перевода — вывести Traefik, когда захочется консолидации, но это не обязательный шаг «на сейчас».

### 8.5. YAML-скетчи (минимальные, проверяемые)

Gateway API: `GatewayClass`, `Gateway` с HTTPS-слушателем для `example.com` и `HTTPRoute` для
`home.example.com`. Обратите внимание на `parentRefs`, `sectionName` и `allowedRoutes` —
это и есть то, чего нет в Ingress-аннотациях.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: homelab
  namespace: default
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: wildcard-tls
      allowedRoutes:
        namespaces:
          from: Same          # только маршруты из своего namespace; кросс-ns — через from: Selector + ReferenceGrant
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: home
  namespace: default
spec:
  parentRefs:
    - name: homelab
      sectionName: https       # привязка именно к HTTPS-слушателю; без sectionName — ко всем списком
  hostnames:
    - home.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: home
          port: 3000
```

Примечания к корректности:

- `parentRefs[].sectionName` обязателен, если маршрут должен цепляться к конкретному слушателю; при его
  отсутствии Route пытается привязаться ко всем совместимым слушателям Gateway.
- `allowedRoutes.namespaces.from`: `Same` (только свой namespace), `All` (любой), `Selector` (по label).
  Кросс-namespace ссылки на `Secret`/`Service` в Route требуют `ReferenceGrant` в целевом namespace —
  это заменяет `allowCrossNamespace` из текущего `values.yaml` Traefik.
- Если оставляем Traefik как Gateway API-провайдер, `GatewayClass` — `traefik.io/gateway-controller`
  (controllerName уточнять по версии Traefik), а не envoy.
- Для ACME: у Envoy Gateway/NGINX Gateway Fabric нет встроенного ACME — сертификат выпускается
  **cert-manager** (`ClusterIssuer` + `Certificate`), который кладёт `Secret` `wildcard-tls`, а Gateway на
  него ссылается. У Traefik ACME встроен и `Certificate`/`Issuer` не нужны. В нашем кластере cert-manager
  **не установлен**, а `wildcard-tls` в Git не описан — это отдельная задача (раздел 10).

### 8.6. Чек-лист миграции

- [ ] Вернуть MetalLB L2 (пул, например, `<metallb-ip>/32`) — `helm install metallb … --set frrk8s.enabled=false`
      (в README сохранилась команда и ссылка на старый манифест пула).
- [ ] Перевести Traefik `Service` с `externalIPs` на `type: LoadBalancer` (фиксированный IP), проверить
      `kubectl get svc -n default traefik`.
- [ ] Убедиться, что policy-routing правило для tailnet (см. `remote-access-metallb-solutions.md`) не сломало
      доступ после смены способа публикации адреса.
- [ ] Установить выбранный Gateway API-контроллер в отдельном namespace; проверить его `GatewayClass`.
- [ ] Поднять тестовый `Gateway` и `HTTPRoute` для одного хоста (`home.example.com`), не трогая Traefik.
- [ ] Прогнать `ingress2gateway` по `k8s/traefik/*.ingress.yaml`, вычитать предупреждения об
      непереводимых аннотациях.
- [ ] Настроить выпуск `wildcard-tls` в Git (cert-manager или SealedSecret), чтобы сертификат не был
      «ручным».
- [ ] После проверки — переключать DNS/маршруты по одному сервису; держать быстрый откат на Traefik.
- [ ] Добавить `DenyServiceExternalIPs` admission, когда `externalIPs` больше нигде не используется.

---

## 9. Рекомендация

**Целевой стек: MetalLB (L2) + Envoy Gateway как Gateway API-реализация, Traefik — временно, до миграции.**
(Вариант C.)

Обоснование:

1. **`externalIPs` надо убирать из-за 1.36.** Это не вкусовщина, а формальная deprecation с планом
   удаления из kube-proxy; в блоге Kubernetes замена — `LoadBalancer` через MetalLB. Значит MetalLB
   возвращается независимо от выбора L7.
2. **Gateway API — отраслевой вектор, а Envoy Gateway — его эталонная реализация** на самом популярном
   data plane: полный core+extended conformance, CNCF-проект (Envoy graduated), живой конвейер
   (366 коммитов/90д). Это лучший «production-grade» навык из доступных.
3. **Traefik не выбрасываем** — он держит 48 маршрутов, встроенный ACME и метрики; миграция должна быть
   постепенной, с откатом. Envoy Gateway поднимается рядом и забирает трафик по одному хосту.
4. **Однонодовость не мешает:** Envoy Gateway — обычные Deployment'ы; внешний адрес ему даёт MetalLB
   (`Service type: LoadBalancer`), как и любому ingress-контроллеру.

Альтернативы и trade-offs:

- **Если цель — минимум работы и максимум сохранения текущего:** вариант B (Traefik + MetalLB, включить
  `kubernetesGateway`). Быстро, но HTTP Core partial, и Traefik — вне CNCF. Подходит как «сделать сейчас»,
  даже если целевой — Envoy Gateway: шаг «убрать externalIPs» общий для B и C.
- **Если хочется чистого NGINX-навыка:** вариант D (NGINX Gateway Fabric) — полный conformance, но
  F5-специфичные policy-CRD и та же возня с cert-manager.
- **Cilium (E)** — объективно сильнее всех, но смена CNI в k0s требует пересоздания кластера; вернуться к
  этому вопросу, если/когда появится вторая нода и желание строить eBPF-стек с LB-IPAM и BGP/L2.
- **Istio/Kong/Higress/APISIX/kgateway** — не для этого homelab: слишком тяжёлые или нишевые.

Отдельно про L4-слой (MetalLB vs kube-vip): оба решают задачу «выдать VIP», оба работают в L2 (ARP) и BGP.
MetalLB — CNCF sandbox и уже был в этом кластере (знаком), поэтому его возврат дешевле; kube-vip — запасной
вариант, если понадобится VIP для control plane.

---

## 10. Открытые вопросы / что проверить в кластере

- **Откуда берётся `wildcard-tls`?** В Git он не описан (нет `kind: Secret`/`SealedSecret` с таким именем).
  Проверить: `kubectl get secret wildcard-tls -n default -o yaml`, срок действия и кто его обновляет.
  Если вручную — перевести на cert-manager/SealedSecret.
- **Актуальна ли версия кластера.** `k8s/k0s/README.md` фиксирует v1.36.3+k0s.2; проверить `k0s version` на
  сервере и решить, когда апгрейдиться (deprecation `externalIPs` уже действует).
- **Возврат MetalLB.** Проверить, свободен ли `<node1-ip>`, и как поведёт себя policy-routing правило
  tailnet с LoadBalancer-IP (в прошлом разборе именно forward-путь ломался; изменение способа публикации
  адреса — риск).
- **Port 80/443 на узле.** Если Gateway API-контроллер будет подниматься рядом с Traefik, нужны разные
  адреса (разные LoadBalancer IP) или разные порты hostNetwork; иначе конфликт.
- **Совместимость Traefik Gateway API-провайдера** с текущей версией чарта 41.4.0 (какой `controllerName`
  и какие профили реально поддержаны в этой версии, а не в отчёте v3.7.10).
- **Переносимость аннотаций.** Прогнать `ingress2gateway` и оценить объём ручной работы: в репозитории
  есть `IngressRoute`/`Middleware`/`ServersTransport`, у которых нет прямого аналога «один-в-один».
- **Данные по ресурсному следу.** Официальных CPU/RAM-профилей у выбранных контроллеров нет; после
  экспериментального развёртывания измерить `kubectl top` для Envoy Gateway vs Traefik на этом хосте и
  зафиксировать в этом документе.

---

## 11. Источники

**Платформа и спецификация:**
- Gateway API — обзор API: https://gateway-api.sigs.k8s.io/concepts/api-overview/
- Gateway API — роли и персоны: https://gateway-api.sigs.k8s.io/concepts/roles-and-personas/
- Gateway API — conformance: https://gateway-api.sigs.k8s.io/concepts/conformance/
- Gateway API — реализации: https://gateway-api.sigs.k8s.io/implementations/
- Gateway API — conformance-отчёты (репозиторий): https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports
- Gateway API v1.6 (TCPRoute/UDPRoute в Standard): https://kubernetes.io/blog/2026/08/03/gateway-api-v1-6-release/
- Ingress | Kubernetes: https://kubernetes.io/docs/concepts/services-networking/ingress/
- Ingress Controllers | Kubernetes: https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/

**Retirement и миграция:**
- Ingress NGINX Retirement (2025-11-11): https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/
- Ingress NGINX: Statement from Steering/SRC (2026-01-29): https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/
- Before You Migrate: Five Surprising Ingress-NGINX Behaviors (2026-02-27): https://kubernetes.io/blog/2026/02/27/ingress-nginx-before-you-migrate/
- Announcing Ingress2Gateway 1.0 (2026-03-20): https://kubernetes.io/blog/2026/03/20/ingress2gateway-1-0-release/
- ingress-nginx README (retirement notice): https://github.com/kubernetes/ingress-nginx
- Datadog Security Labs (2026-02-19): https://securitylabs.datadoghq.com/articles/kubernetes-ingress-nginx-retirement-warning/

**externalIPs (важно для текущего homelab):**
- Kubernetes v1.36: Deprecation and removal of Service ExternalIPs (2026-05-14): https://kubernetes.io/blog/2026/05/14/deprecation-of-service-externalips/
- ExternalPolicyForExternalIP feature gate: https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/

**Conformance-отчёты (первоисточники):**
- Cilium standard v1.20.0: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/cilium/standard-v1.20.0-default-report.yaml
- Envoy Gateway v1.9.0: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/envoy-gateway/experimental-v1.9.0-default-report.yaml
- Istio v1.31.0: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/istio-istio/1.31.0-default-report.yaml
- kgateway v2.4.0-rc.1: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/kgateway/v2.4.0-rc.1-report.yaml
- Kong Operator v2.3.1: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/kong-operator/experimental-v2.3.1-traditional_compatible-standard-report.yaml
- NGINX Gateway Fabric v2.7.0: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/nginx-nginx-gateway-fabric/experimental-2.7.0-default-report.yaml
- Traefik v3.7.10: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/traefik-traefik/experimental-v3.7.10-default-report.yaml
- Higress v2.2.4: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/higress-group-higress/standard-v2.2.4-default-report.yaml
- HAProxy Ingress/N42 v0.17.0-alpha.1: https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.5/haproxy-ingress/experimental-v0.17.0-alpha.1-default-report.yaml

**Проекты:**
- Traefik — provider Kubernetes Gateway API: https://doc.traefik.io/traefik/providers/kubernetes-gateway/
- Envoy Gateway docs: https://gateway.envoyproxy.io/docs/
- NGINX Gateway Fabric — Gateway API compatibility: https://docs.nginx.com/nginx-gateway-fabric/overview/gateway-api-compatibility/
- Kong Ingress Controller — Gateway API: https://docs.konghq.com/kubernetes-ingress-controller/latest/concepts/gateway-api/
- Cilium — Gateway API: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
- Contour — Gateway API: https://projectcontour.io/docs/main/config/gateway-api/
- APISIX Ingress — Gateway API: https://apisix.apache.org/docs/ingress-controller/concepts/gateway-api/
- Gloo OSS EOL / kgateway: https://github.com/solo-io/gloo ; https://github.com/kgateway-dev/kgateway
- N42 Gateway (ex-HAProxy Ingress): https://github.com/n42-gateway/n42-gateway
- Calico — About (Ingress Gateway — Enterprise/Cloud): https://docs.tigera.io/calico/latest/about/
- MetalLB — L2 mode: https://metallb.universe.tf/concepts/layer2/
- kube-vip — LoadBalancer service: https://kube-vip.io/docs/usage/kubernetes-services/

**Фонды/опросы:**
- CNCF Annual Survey 2024 (нет разбивки по ingress-контроллерам): https://www.cncf.io/reports/cncf-annual-survey-2024/
- CNCF landscape (maturity проектов): https://github.com/cncf/landscape

**GitHub REST API:**
- Числа по звёздам/форкам/issues/контрибьюторам/релизам собраны 17.09.2026 через `gh api repos/<owner>/<repo>`,
  `.../releases/latest` и `.../contributors?per_page=1&anon=true`; активность — `.../commits?since=2026-06-17`.
