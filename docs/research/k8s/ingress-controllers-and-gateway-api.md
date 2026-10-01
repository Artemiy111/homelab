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

> Дополнено 2026-10-01: разделы 7bis (Gateway API: устройство, история, что не стандартизировано,
> выбор реализации) и 7ter (ресурсный след: дефолты чартов + фактические измерения на узле).
> Фактическое состояние кластера, варианты миграции и рекомендация приведены в соответствие
> с выполненной миграцией (#700, `docs/adr/0010-gateway-api-routing.md`).
>
> Дата исходного исследования: 2026-09-17. Кластер в репозитории — k0s **v1.36.3+k0s.2**
> (см. `platform/k0s/README.md`), CNI — Calico v3.32.1 (vxlan), kube-proxy в режиме iptables,
> один узел Fedora Server 44. Актуальная версия Gateway API — **v1.6.2** (релиз 2026-09-03).

Дата исследования: 2026-09-17, дополнено 2026-10-01. Кластер в репозитории — k0s **v1.36.3+k0s.2** (см. `platform/k0s/README.md`),
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
  `Middleware`/`ServersTransport`/`TLSStore`. В этом репозитории `Middleware` лежат рядом с
  приложениями (`apps/<сервис>/k8s/*.middleware.yaml`, `platform/traefik/`), а `TLSStore`
  остался как legacy для `traefik-healthcheck`.
- **Gateway API:** провайдер `kubernetesGateway` включён, обслуживает 48 `HTTPRoute`. По отчёту
  v3.7.10 профиль **HTTP: Core = partial** (пропущен тест `HTTPRouteMultipleGateways`),
  Extended = success; GRPC/TLS — Core success
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.6/traefik-traefik/experimental-v3.7.10-default-report.yaml)).
- **ACME:** встроенный ACME-клиент (Let's Encrypt, в т.ч. HTTP-01/TLS-ALPN/DNS-01);
  TLSStore/defaultCertificate. **В кластере ACME не используется** — сертификат выпускает
  cert-manager (`platform/homelab/templates/cert-manager/certificate.yaml`), встроенный клиент
  оставлен на случай ручного выпуска.
- **Фичи:** middleware-цепочки (headers, forwardAuth, rateLimit, redirect, stripPrefix), балансировка,
  TCP/UDP, WebSocket/HTTP2/gRPC, метрики Prometheus (включены в `platform/traefik/values.yaml`).
- **Слабые стороны:** Gateway API-поддержка неполная (HTTP Core partial; нет `HTTPRouteRetry*`,
  `HTTPRouteRequestTimeout`, `HTTPRouteCORS`, `HTTPRouteRequestMirror`, frontend mTLS — см. 7bis.3);
  нет WAF из коробки; MIT и вне CNCF — governance зависит от одной компании (Traefik Labs).
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

## 7bis. Gateway API: что это за стандарт и чем он отличается от Ingress

### 7bis.1 История появления

| Событие | Дата |
|---|---|
| Репозиторий `kubernetes-sigs/gateway-api`, Initial commit | **1 ноября 2019** |
| Первый релиз `v0.1.0` | 18 ноября 2020 |
| `v0.4.0` — последний 0.x | 14 октября 2021 |
| **`v1.0.0` — первый GA** | **31 октября 2023** |
| `v1.2.0` | 3 октября 2024 |
| `v1.6.2` (в кластере) | 3 сентября 2026 |

Проект начинался как SIG Network / separate repo и **четыре года** шёл к `v1.0.0` — в отличие от
EndpointSlice (2019, Kubernetes 1.17, 9 декабря), где узкое место закрыли за один релиз. Причина в том,
что Gateway API — не доработка существующего API, а новый пользовательский API, и версии `v0.x` не
совпадали с версиями Kubernetes.

**EndpointSlice для контраста:** alpha в 1.16 (сентябрь 2019), beta в 1.17 (9 декабря 2019),
GA (`discovery.k8s.io/v1`) в 1.21 (апрель 2021), v1 `Endpoints` помечен deprecated в 1.33.

### 7bis.2 Смена модели: три роли вместо одной сущности

Ingress склеивал три вещи в одном объекте. Gateway API их разделил:

| Объект | Что описывает | Ближайший аналог в Ingress |
|---|---|---|
| `GatewayClass` | кто реализует (controllerName) | `ingressClassName` |
| `Gateway` | **где входит трафик**: порт, протокол, TLS, `certificateRef`, `allowedRoutes` | ничего отдельного — только аннотации контроллера |
| `HTTPRoute` | **как маршрутизировать**: hostnames, matches, filters, backendRefs | сам `Ingress` |

Практические следствия, проверенные на стенде при переводе 49 маршрутов:

- **TLS стал частью входа, а не маршрута.** Схема «`TLSStore default` как fallback для любого SNI»
  заменена на `certificateRef` на слушателе `Gateway` — адресуемое место вместо магии.
- **Маршрут перестал быть источником правды о том, где вход.** Раньше 49 файлов неявно предполагали,
  что Traefik слушает `websecure` на 443; теперь это объявлено один раз.
- **`allowedRoutes` заменил `allowCrossNamespace`.** Неявная связность стала явным правилом.
- **Предсказуемость приоритетов.** В `IngressRoute` приоритет считался из длины строки правила,
  поэтому его приходилось задавать руками (`priority: 110`). В `HTTPRoute` он выводится из
  спецификации (`httproute.go:766-814`): Exact `+100000`, PathPrefix `+10000 + длина×100`,
  method `+1000`, header `+100` каждый. Точное совпадение всегда выигрывает у префикса, порядок
  правил работает как ожидаешь.

### 7bis.3 Чего Gateway API не стандартизировал

**Это главный вывод для выбора реализации.** Проверено по схемам CRD v1.6.2 и по исходникам Traefik
v3.7.12:

| Возможность | В API v1 | Комментарий |
|---|---|---|
| `rateLimit` | **отсутствует** | В `HTTPRouteFilterType` есть `CORS`, `RequestMirror`, `RequestRedirect`, `URLRewrite`, `Request/ResponseHeaderModifier`, `ExtensionRef`, `ExternalAuth` — rate limit среди них нет |
| `forwardAuth` | **в experimental** | `ExternalAuth` помечен `<gateway:experimental>`, в standard-канале отсутствует |
| frontend mTLS | **нет** | `GatewayFrontendClientCertificateValidation` и соседние — unsupported у Traefik v3.7.12 |
| retry / timeout | **нет** | `HTTPRouteRetry*`, `HTTPRouteRequestTimeout` — unsupported |
| кросс-namespace `Middleware` | **механизма нет** | см. 7bis.4 |

То есть по сравнению с Ingress стандартизовано ровно то, что и так было одинаковым у всех
контроллеров: хост, путь, порт, TLS-сертификат. Всё трафик-специфичное — авторизация, rate limit,
заголовки, regex-редиректы — осталось в диалекте реализации.

### 7bis.4 Ограничение, которое ломает наивный подход

**`ExtensionRef` разрешает `Middleware` только в своём namespace.** `extensionRef` имеет тип
`LocalObjectReference` (поля `namespace` нет), а `loadHTTPRouteFilterExtensionRef`
(`httproute.go:481`) передаёт в колбэк namespace **самого** `HTTPRoute`. Проверено пробой на стенде:
`middleware "monitoring-secure-headers@kubernetescrd" does not exist`, при том что объект в кластере
есть и лежит в `traefik`.

Следствие: `allowCrossNamespace: true` решает эту задачу для `IngressRoute` одной строкой, а
Gateway API заставляет **размножить** политики. В нашем репозитории это 27 копий трёх middleware
(`oauth2-proxy` ×7, `secure-headers` ×12, `ratelimit-default` ×8) — Gateway API в этом смысле ухудшил
то, что раньше работало.

`ReferenceGrant` покрывает кросс-namespace ссылки на `Service` и `Secret`, но **не** на `Middleware`
или иные CRD-расширения.

### 7bis.5 Выбор реализации по нашим требованиям

Требования, выявленные при переводе 49 маршрутов: forward-auth через oauth2-proxy (9 хостов),
rate limit 100 r/s burst 50 (8 хостов), заголовки HSTS/XFO/nosniff (12 хостов), stripPrefix
(4 хоста), regex-редирект (2 места), `nativeLB` для hostNetwork-подов (3 сервиса).

| Возможность | Traefik v3.7.12 | Envoy Gateway v1.9.2 | N42 v0.16.2 | NGINX Fabric v2.7.2 |
|---|---|---|---|---|
| forward-auth | ✅ `Middleware` | ✅ `SecurityPolicy.spec.extAuth.http` + `ReferenceGrant` | ⚠️ аннотация на backend Service, Lua | ✅ `SecurityPolicy` |
| rate limit | ✅ нативно | ✅ `BackendTrafficPolicy.spec.rateLimit.local` | ⚠️ аннотация `limit-rps` | ⚠️ частично NAP |
| заголовки | ✅ `Middleware` | ✅ `ClientTrafficPolicy.spec.headers.lateResponseHeaders` | ⚠️ response-only, и то в alpha | ✅ |
| stripPrefix / replacePath | ✅ | ✅ `URLRewrite` | ❌ `HTTPRoutePathRewrite` unsupported | ✅ |
| regex-редирект | ✅ `redirectRegex` | ❌ нет; только `Exact` + `RequestRedirect` | ❌ | ⚠️ |
| nativeLB (hostNetwork) | ✅ `traefik.io/service.nativelb` | ✅ `BackendTrafficPolicy.spec.routingType: Service` | ⚠️ hostNetwork/hostPort у самого n42 | — |
| policy на маршруте | ✅ `filters[].extensionRef` | ✅ `extensionRef` → `HTTPRouteFilter` | ❌ политика уезжает на Service | ✅ |
| **кросс-namespace policy** | ❌ same-namespace | ✅ `targetSelectors.namespaces.from: All` (v1.8+) | — | ✅ |
| TraefikService / `api@internal` | ✅ | ❌ `backendRefs` только Service/ServiceImport/Backend | ❌ | ❌ |

**Два вывода, которые стоит запомнить:**

1. **Envoy Gateway выигрывает на кросс-namespace политиках.** Одна `SecurityPolicy` с
   `targetSelectors.namespaces.from: All` заменяет 27 копий. Это ровно та проблема, которую создал
   Traefik. Цена — `ReferenceGrant` в каждом целевом namespace (маленький объект, но поштучно).
2. **Traefik выигрывает на `rateLimit` semantics.** У Envoy в CRD есть только `limit.requests` +
   `limit.unit` — **поля `burst` нет**, и счётчик per-route: политика на Gateway даст 8 независимых
   корзин по 100 r/s вместо одной общей. Ближайший эквивалент `burst: 50` не верифицирован и требует
   эксперимента на живом data plane.

### 7bis.6 Поведенческие различия, о которых стоит знать заранее

- **Wildcard-слушатель не покрывает apex.** `findMatchingHostname` (`kubernetes.go:1201`)
  проверяет `HasSuffix` по `*.example.com`, поэтому `example.com` не пересекается с
  `*.example.com`. Для apex нужен отдельный слушатель — в нашем `Gateway` их два: `https` и `apex`.
- **Gateway-роутер молча перебивает CRD-роутер.** Приоритет от длины правила: Gateway ~10000 против
  CRD ~24. Если применить `HTTPRoute`, не удалив `IngressRoute`, старый маршрут не «продолжит
  работать», а будет незаметно вытеснен, без warning'а.
- **Envoy по умолчанию** делает `mergeSlashes: true` и `UnescapeAndRedirect` для `%2f`/`%5c`,
  что отдаёт **301** на экранированные слеши. Traefik так не делает.
- **`backendRefs[].port` — только число** (`Port *PortNumber`). В Ingress допустимо имя порта
  (`port.name`); при переводе `forgejo` это дало 404, пока `port: http` не заменили на `port: 80`.

---

## 7ter. Ресурсный след: сколько реально потребляет каждое решение

Заполняет пробел, помеченный в исходном исследовании как «не измерялось». Данные из двух источников:
дефолты из чартов/манифестов проектов на зафиксированных версиях (раздел 7ter.1) и **фактические
измерения на нашем узле** (раздел 7ter.2).

### 7ter.1 Дефолты requests/limits из чартов

Главная находка: **большинство проектов не поставляют resource-дефолтов вообще.** Там, где стоит
`resources: {}`, kubelet относит поды к BestEffort — они первыми вытесняются под давлением и не имеют
ни гарантии, ни ограничения.

| Реализация | Версия | Control plane | Data plane | Прочее | Подов | Источник |
|---|---|---|---|---|---|---|
| **Envoy Gateway** | v1.9.2 | **100m / 256Mi** (limit 1024Mi) | **100m / 512Mi** | shutdown-mgr 10m/32Mi; certgen Job `{}` | 4 | `charts/gateway-helm/values.yaml:64-69`; `api/v1alpha1/shared_types.go:25,27` |
| **Traefik** | chart 41.4.0 | `resources: {}` — **нет дефолтов** | н/д (один процесс) | — | 1 | `values.yaml:1227`, рендерится в `resources: null` |
| **NGINX Gateway Fabric** | v2.7.2 | `{}` | `{}` | — | 1 + Job | `charts/nginx-gateway-fabric/values.yaml:223,810` |
| **N42 Gateway** | v0.16.2 | `{}` | тот же под | сайдкар haproxy `{}`, off | 1 | `charts/haproxy-ingress/values.yaml:266,432` |
| **N42 Gateway** | v0.17.0-alpha.3 | `{}` | тот же под | 3 опц. компонента, все `{}` | 1 | `charts/n42-gateway/values.yaml:284,450,521,614` |
| **Kong IC** | v3.5.13 | `{}` | `{}` (отдельный контейнер `proxy`) | — | 1 (2 контейнера) | `values.yaml:809,630,474` |
| **Contour** | v1.33.7 | **нет блока resources** | нет | init-контейнеры без ресурсов | **2 ctrl + 1 envoy DS/node** | `examples/contour/03-contour.yaml` |
| **Istio** (только gateway) | 1.31.0 | istiod **500m / 2048Mi** | istio-proxy 100m / 128Mi | waypoint 100m/128Mi | 2 | `istio-discovery/values.yaml:21-24`; `gateway/values.yaml:75-81` |
| **Cilium** | v1.20.2 | operator `{}` | agent `{}` (gateway живёт в агенте) | cni init 100m/10Mi; operator 2 реплики | 2 DS + 2 | `install/kubernetes/cilium/values.yaml:337` |
| **kgateway** | v2.4.5 | `null` / `{}` | н/д | — | 1 | `install/helm/kgateway/values.yaml:39,86` |
| **Higress** | v2.2.4 | `higress-core` 500m/2048Mi + `pilot` 500m/2048Mi | gateway **2000m / 2048Mi** | — | 3 (gateway 2 реплики) | `helm/core/values.yaml:529,648,683` |
| **ingress-nginx** (retired) | v1.15.1 | 100m / 90Mi | н/д | webhook Job `{}` | 1 + 2 Job | `charts/ingress-nginx/values.yaml:397-403` |
| **haproxytech/ingress** | v3.2.15 | **2048Mi** request, без CPU | тот же под | — | 1 | `deploy/haproxy-ingress.yaml:168-172` |

**Envoy Gateway — единственная Gateway-API-нативная реализация с настоящими дефолтами для обеих плоскостей.**
Её data-plane дефолты живут в Go-коде, а не в чарте, поэтому `helm show values` их не покажет.

**Higress отпадает по ресурсу:** 8192Mi requests на трёх подах (gateway с двумя репликами) — примерно
x10 от минимальных вариантов.

### 7ter.2 Фактические измерения на нашем узле

Снято `kubectl top` и сверено с requests на живом кластере 2026-10-01.

**Узел:**

| Метрика | Значение |
|---|---|
| Всего памяти | 27.2 GiB |
| Allocatable | 26.1 GiB |
| **Занято фактически** | **21.9 GiB = 84%** |
| Сумма requests всех подов | **23.2 GiB** |
| Сумма limits | 124.5 GiB |
| CPU | 16 ядер, фактически 4.1 (25%) |

**Наш Traefik в работе:**

| Показатель | Значение |
|---|---|
| Фактическое потребление | **8m CPU, 91Mi RAM** |
| Requests | 192Mi (CPU не задан) |
| Limits | 384Mi |
| Подов | 1 |

То есть **фактическое потребление Traefik на 48 маршрутах — 91Mi**, а requests 192Mi задан с запасом.
Это эталон для сравнения.

**Арифметика переезда на Envoy Gateway:**

```
Envoy requests:  256Mi (control plane) + 512Mi (data plane) + 512Mi (ratelimit) = 1280Mi
Traefik сейчас:  192Mi
Прирост:                                                 +1088Mi = +1.06 GiB  (x6.7)
```

Дополнительно: `ratelimit`-деплоймент создаётся всегда, независимо от наличия rate-limit политик
(образ `docker.io/envoyproxy/ratelimit` присутствует в чарте безусловно). Если rate limit через
`BackendTrafficPolicy` не понадобится, его можно убрать — тогда прирост +512Mi вместо +1.06 GiB.

**Итог по бюджету памяти:**

```
Свободно по requests:  26.1 - 23.2 = 2.9 GiB
Envoy Gateway:         +1.06..1.25 GiB
Планка requests:       23.2 + 1.25 = 24.5 GiB из 26.1 = 94%
```

**Envoy Gateway не помещается без освобождения памяти.** Крупнейший потребитель — `longhorn
instance-manager` (2.3 GiB), а на одной ноде распределённое хранилище не даёт выгоды.

Замеры фактического потребления (не requests) для остальных реализаций не проводились: у них в
основном нет дефолтов, и единственный честный способ получить цифры — поставить и снять `kubectl top`
на своём хосте. Чарты с `resources: {}` не дают верхней границы: реальное потребление нашего Traefik
(91Mi) — это то, что он занял сам, а не то, что ему выдали.

### 7ter.3 Вывод по ресурсам

1. **Для нашего кластера решает не footprint контроллера, а свободная память.** При 84% занятости
   и requests 23.2 из 26.1 GiB добавление 1.25 GiB — это треть свободного места.
2. **Envoy Gateway дорог по requests, но не по факту.** Его 800Mi+ — верхняя граница от дефолтов;
   реальное потребление data plane на 48 маршрутах, вероятно, ниже, но это нужно мерить.
3. **N42 Gateway — самый лёгкий по архитектуре:** один под (контроллер + HAProxy + сайдкары), без
   split control/data plane, без ratelimit-деплоймента, zero-copy reload через master-worker сокет.
   По footprint он вне конкуренции — но см. блокеры в 7ter.4.
4. **Istio и Higress отпадают по ресурсу** (2176Mi и 8192Mi requests).
5. **Многие чарты не задают resources.** Для одноузлового кластера это терпимо, но означает
   BestEffort-поды без гарантий — их придётся описать самим.

### 7ter.4 Почему N42 Gateway не мигрируют, несмотря на лёгкость

Проверено по документации релиза и по исходникам проекта:

- **В стабильной версии нет ни фильтров, ни status.** Документация `v0.16.2` (2026-09-20) говорит
  дословно: «HTTPRoute's Rules and BackendRefs don't support Filters» и «Resources status are not
  updated» ([gateway-api.md @ release-0.16](https://github.com/n42-gateway/n42-gateway/blob/release-0.16/docs/content/en/docs/configuration/gateway-api.md)).
  Всё, что у нас делается через `Middleware`, — это фильтры. Без `status` Argo CD не покажет
  состояние синхронизации.
- **Фильтры появились только в `v0.17.0-alpha.3`** (пререлиз), и даже там conformance-отчёт помечает
  `HTTPRoutePathRewrite`, `HTTPRouteRequestTimeout`, `HTTPRouteMethodMatching`,
  `HTTPRouteQueryParamMatching` как unsupported
  ([отчёт](https://github.com/kubernetes-sigs/gateway-api/blob/main/conformance/reports/v1.5/n42-gateway/experimental-v0.17.0-alpha.3-default-report.yaml)).
- **Bus factor = 1:** в `maintainers` чарта один человек, CNCF-управления нет.
- **Политика уезжает с маршрута на Service.** forward-auth работает через аннотацию на backend
  Service (`auth-url: svc://oauth2-proxy/oauth2/auth` с Lua-скриптом), а доки прямо говорят:
  «Gateway API resources don't support annotations». Per-path гранулярность становится
  невыразимой — Path scope схлопывается.
- **Доки противоречат коду.** Документация v0.17 утверждает полную конформантность, но
  `pkg/converters/gateway/gateway.go` содержит `TODO implement Filters[]` и
  `TODO implement Addresses[]`. Вывод по опубликованным докам будет неверным.

**Рекомендация:** мониторить, не внедрять. Пересмотреть, когда `v0.17` станет stable и появится
отчёт за standard-канал.

### 7ter.5 Как адрес публикуется — от proxychoice не зависит

Отдельно стоит зафиксировать, потому что `externalIPs` устаревает в 1.36, а срок ближе, чем кажется.

| Версия | Стадия по KEP-5707 |
|---|---|
| v1.36 | Deprecated, только предупреждения — **мы здесь** |
| v1.40 | Отключено по умолчанию |
| v1.43 | Реализация удалена |
| v1.46 | Cleanup |

До удаления — четыре релиза, то есть это отслеживаемая задача, а не инцидент. Причина депrecation'а —
CVE-2020-8554 (`externalIPs` позволяет перехватить чужой IP), но сам CVE **не исправлен**
([kubernetes/kubernetes#97076](https://github.com/kubernetes/kubernetes/issues/97076) открыт): KEP-5707 —
механизм депrecation, выбранный отчасти потому, что починить CVE нельзя.

Способ получения внешнего адреса одинаков для всех реализаций и **не влияет на выбор L7**:
`LoadBalancer` + облачный LB (на голом Fedora без cloud controller `status.loadBalancer.ingress`
останется пустым), MetalLB, kube-vip (только L2, без L7), `hostNetwork`/NodePort, либо LB-IPAM самой
CNI (Cilium). Для нашего кластера — MetalLB L2 + `Service type: LoadBalancer`, и это **отдельная
задача, независимая от выбора контроллера**.

---

## 8. Что стоит в homelab сейчас и варианты миграции

### 8.1. Фактическое состояние (проверено по репозиторию)

| Компонент | Факт | Источник |
|---|---|---|
| Кластер | k0s **v1.36.3+k0s.2**, один узел Fedora Server 44 | `platform/k0s/README.md:9` |
| CNI | **Calico v3.32.1, vxlan**, kube-proxy iptables | `etc/k0s/k0s.yaml.j2` |
| Реализация Gateway | **Traefik**, Helm chart 41.4.0 (образ v3.7.12), `GatewayClass traefik` | `argocd/applications/traefik.yaml:11` |
| Адрес входа | `Service type: ClusterIP` + **`externalIPs: [<node1-ip>]`** | `argocd/applications/traefik.yaml:24-31` |
| MetalLB | **удалён** («на одном узле не нужен — kube-proxy externalIPs достаточно») | `platform/k0s/README.md:182-196` |
| Маршруты | **48 `HTTPRoute`** в `apps/<сервис>/k8s/route.yaml`; `Ingress`/`IngressRoute` в репозитории не осталось | `apps/`, `platform/` |
| Gateway | `Gateway homelab` в namespace `traefik`, слушатели `https` (`*.<домен>`) и `apex` | `platform/homelab/templates/gateway/gateway.yaml` |
| TLS | cert-manager v1.21.2, `Certificate wildcard` → `wildcard-tls` в `traefik`, DNS-01 через webhook | `platform/homelab/templates/cert-manager/certificate.yaml` |
| DNS | Technitium, wildcard `*.<домен>` → `<node1-ip>` | `terraform/technitium/records.tf` |
| Tailscale | на хосте, subnet route + split DNS; доступ из tailnet починен policy-routing правилом | `docs/troubleshot/tailscale-k8s-ingress-access.md` |

**Состояние на 2026-10-01: миграция на Gateway API выполнена** (#700, PR #701–#706, решение
в `docs/adr/0010-gateway-api-routing.md`). Реализация — Traefik с включённым
`providers.kubernetesGateway`, Gateway API CRD v1.6.2 standard ставятся отдельным
Argo-приложением (`argocd/applications/gateway-api.yaml`): чарт Traefik их не везёт
с версии 40.2.0, а `skipCrds: true` на них не действует.

**Поправка к «известному контексту»:** утверждения этого раздела, оставшиеся от
исследования 2026-09-17, в части маршрутов, cert-manager и расположения файлов
устарели. Актуальные факты — в таблице выше и в `docs/adr/0010-gateway-api-routing.md`.

### 8.2. Две проблемы, которые надо решить в любом случае

1. **`Service.spec.externalIPs` устарел в Kubernetes 1.36** — а у нас ровно 1.36.3. Поле формально
   deprecated; ожидается, что будущий минорный релиз **уберёт поддержку из kube-proxy** и потребует от
   conformant-реализаций *не* поддерживать его. Первоисточник:
   [Kubernetes v1.36: Deprecation and removal of Service ExternalIPs](https://kubernetes.io/blog/2026/05/14/deprecation-of-service-externalips/)
   (2026-05-14). Причина — CVE-2020-8554: `externalIPs` позволяет «угнать» чужой IP, т.к. API предполагает
   полностью доверенных пользователей. Рекомендуемая замена в блоге — **`type: LoadBalancer` через
   не-облачный LB-контроллер, например MetalLB**. Это прямо возвращает нас к удалённому MetalLB.
2. **Gateway API — не «дроп-ин» для Ingress.** `ingress2gateway` неприменим: конвертирует две
   traefik-аннотации из ~40 и не читает `IngressRoute`/`Middleware`. Все 49 маршрутов переведены
   вручную; `ServersTransport` для выведенного из эксплуатации elk удалён вместе с сервисом,
   `scheme: h2c` оказался не нужен — `HTTPRoute` определяет протокол по Upgrade-заголовкам.
   Полный разбор дыр — 7bis.3, 7bis.5 и `docs/adr/0010-gateway-api-routing.md`.

### 8.3. Варианты — историческая ретроспектива

> **Этот раздел описывает варианты, как они выглядели 2026-09-17. Выбранный вариант реализован:**
> Gateway API с Traefik в роли реализации (#700, `docs/adr/0010-gateway-api-routing.md`).
> Разбор ниже сохранён как обоснование выбора; актуальные решения — в 7bis.5 и 7ter.

| Вариант | Плюсы | Минусы | Итог |
|---|---|---|---|
| **A. Оставить как есть (Traefik + externalIPs)** | 0 работы | `externalIPs` deprecated; безопасности нет (CVE-2020-8554 класс) | ❌ не рекомендуется |
| **B. Traefik + вернуть MetalLB L2, остаться на Ingress/IngressRoute, включить Gateway API-провайдер Traefik** | Минимум изменений; отдаём `<node1-ip>`/`<node1-vip>` законно; ACME и TLS уже работают; можно постепенно переводить маршруты | HTTP Core partial; Gateway API-скилл ограничен; Governance/лицензия вне CNCF | ✅ **реализовано** (кроме MetalLB) |
| **C. Traefik для старых маршрутов + Envoy Gateway как Gateway API-реализация + MetalLB L2** | Полный conformance (core+extended); Envoy — индустриальный data plane; чистый Gateway API-скилл; отраслевой вектор | +1 control plane/data plane на одноузловом кластере; ACME через cert-manager; нужен отдельный адрес/порт | ⏸ отложено: **не помещается по памяти** (7ter.2) |
| **D. NGINX Gateway Fabric + MetalLB L2** | Полный conformance; NGINX-скилл; проще, чем Envoy-модель | Та же история с cert-manager; F5-специфичные политики; ещё один прокси рядом с Traefik | Альтернатива C |
| **E. Cilium Gateway API (заменить Calico)** | Самый мощный: eBPF, LB-IPAM, BGP/L2, full conformance | Смена CNI в k0s = пересоздание кластера; большой объём работ | Отложить |
| **F. Istio / Kong / Higress / APISIX / kgateway** | Много фич | Сильно избыточно для homelab; каждая — отдельный «зоопарк» | ❌ (Higress и Istio отпадают ещё и по ресурсу) |

**Что из варианта B не сделано:** возврат MetalLB. Он остаётся открытой задачей,
независимой от выбора L7 (7ter.5).

### 8.4. Что делать с текущим reverse proxy

**Traefik остаётся реализацией Gateway API.** На нём 48 `HTTPRoute`; выводить его нечем, пока
`Middleware` востребованы авторизацией (7bis.3: `forwardAuth` в стандартном канале Gateway API
отсутствует).

Оставшиеся шаги:

1. **Убрать зависимость от `externalIPs`:** MetalLB L2 + `Service type: LoadBalancer`
   с фиксированным IP из пула. Покрывает deprecated-API, сохраняет `wildcard-tls` и все
   `HTTPRoute` без правок.
2. **Освободить память под возможный переезд на Envoy Gateway** (разбор потребления;
   `longhorn` на одной ноде — крупнейший потребитель, 7ter.2).
3. **Не плодить `redirectRegex`.** Аналога в Envoy Gateway нет (7bis.5); переводить на
   `Exact` + `RequestRedirect` заранее.
4. **Убрать `traefik.io/service.nativelb` из Service** при переезде, заменив на
   `BackendTrafficPolicy.spec.routingType: Service`.

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

**Выполнено (миграция на Gateway API, #700):**

- [x] Gateway API CRD v1.6.2 standard отдельным Argo-приложением
- [x] `GatewayClass traefik` + `Gateway homelab` со слушателями `https` и `apex`
- [x] `providers.kubernetesGateway.enabled: true` в values Traefik
- [x] Все 29 `Ingress` → `HTTPRoute` в `apps/<сервис>/k8s/route.yaml`
- [x] Все 20 `IngressRoute` → `HTTPRoute`, `stripPrefix`/`replacePath` → `URLRewrite`
- [x] `nativeLB` перенесён аннотацией `traefik.io/service.nativelb` на 3 Service
- [x] `HeaderRegexp` (rustfs) → нативный match по заголовку
- [x] Каталог `platform/homelab/templates/routes/` удалён

**Осталось:**

- [ ] Вернуть MetalLB L2 — `helm install metallb … --set frrk8s.enabled=false`
      (команда и ссылка на прежний манифест пула сохранены в `platform/k0s/README.md:182-196`).
- [ ] Перевести Traefik `Service` с `externalIPs` на `type: LoadBalancer` (фиксированный IP).
- [ ] Убедиться, что policy-routing правило для tailnet
      (`docs/troubleshot/tailscale-k8s-ingress-access.md`) не сломало доступ после смены
      способа публикации адреса.
- [ ] Добавить `DenyServiceExternalIPs` admission, когда `externalIPs` больше нигде не используется.

**Понадобится при переезде на другую реализацию:**

- [ ] `routingType: Service` на трёх hostNetwork-сервисах — единственное, что может уронить
      хосты в первый день (бесконечный loop против самого gateway).
- [ ] Перенести 27 копий `Middleware` в одну `SecurityPolicy` c
      `targetSelectors.namespaces.from: All` + `ReferenceGrant` в каждом namespace.
- [ ] Заменить два `redirectRegex` на `Exact` + `RequestRedirect` — аналога в Envoy Gateway нет.
- [ ] Решить вопрос `rateLimit` без поля `burst` и с per-route счётчиком.
- [ ] Дашборд (`api@internal`) — аналога нет, маршрут придётся убрать.
- [ ] `egctl x translate` в проверки PR: ловит ошибки CEL и `ReferenceGrant` до кластера.

---

## 9. Рекомендация

> **Обновлено 2026-10-01.** Исходная рекомендация (MetalLB + Envoy Gateway + Traefik временно)
> **не реализована в части Envoy Gateway.** Миграция выполнена на варианте B: Gateway API с
> Traefik в роли реализации. Ниже — актуальная позиция; исходное обоснование сохранено.

**Текущий стек: Gateway API v1.6.2 + Traefik v3.7.12 как реализация + cert-manager для TLS.**
Место MetalLB не занято, вместо него `externalIPs`.

1. **Переход на Gateway API сделан, и это правильный шаг независимо от выбора реализации.**
   Разделение ролей и типизированные поля — то, что Ingress дать не мог, а маршруты лежат
   рядом с приложениями.
2. **Traefik остаётся, потому что альтернативы хуже по нашим требованиям, а не потому
   что он лучше.** `forwardAuth` в стандартном канале Gateway API отсутствует (7bis.3),
   поэтому девять хостов за oauth2-proxy держатся на Traefik-специфичном `Middleware`.
3. **Envoy Gateway отложен по памяти, а не по качеству.** Он сильнее по conformance и
   единственный закрывает кросс-namespace политики, но +1.06..1.25 GiB requests при
   бюджете 2.9 GiB свободных — это 94% планки (7ter.2). Освобождение памяти должно
   предшествовать, а не сопутствовать смене контроллера.
4. **`externalIPs` — задача с дедлайном, не с аварийкой.** Deprecated в 1.36, удалён в 1.43
   (7ter.5). Это отдельная работа, не связанная с выбором L7.
5. **Ingress API мёртв как вариант:** ingress-nginx архивирован 0 коммитов за 90 дней,
   и ни один из оставшихся проектов не предлагает его как целевое состояние.
  этому вопросу, если/когда появится вторая нода и желание строить eBPF-стек с LB-IPAM и BGP/L2.
- **Istio/Kong/Higress/APISIX/kgateway** — не для этого homelab: слишком тяжёлые или нишевые.

Отдельно про L4-слой (MetalLB vs kube-vip): оба решают задачу «выдать VIP», оба работают в L2 (ARP) и BGP.
MetalLB — CNCF sandbox и уже был в этом кластере (знаком), поэтому его возврат дешевле; kube-vip — запасной
вариант, если понадобится VIP для control plane.

---

## 10. Открытые вопросы / что проверить в кластере

> Обновлено 2026-10-01. Вопросы, закрытые миграцией на Gateway API, отмечены.

**Закрыто:**

- ✅ **Откуда берётся `wildcard-tls`.** cert-manager v1.21.2, `Certificate wildcard` в
  `platform/homelab/templates/cert-manager/certificate.yaml`, DNS-01 через собственный webhook.
  Секрет `wildcard-tls` в namespace `traefik`, Gateway ссылается через `certificateRef`.
- ✅ **Совместимость Traefik Gateway API-провайдера** с чартом 41.4.0 (образ v3.7.12):
  `controllerName: traefik.io/gateway-controller`, Gateway API v1.6.2, `ExtensionRef` для
  `Middleware` работает. Не поддерживаются `HTTPRouteRetry*`, `HTTPRouteRequestTimeout`,
  `HTTPRouteCORS`, `HTTPRouteRequestMirror`, `ListenerSet`, frontend mTLS.
- ✅ **Переносимость аннотаций.** `ingress2gateway` неприменим: конвертирует 2 traefik-аннотации
  из ~40 и не читает `IngressRoute`/`Middleware`. Все 49 маршрутов переведены вручную.
- ✅ **Данные по ресурсному следу** — см. 7ter.1 и 7ter.2.
- ✅ **Port 80/443** — отдельная реализация рядом с Traefik потребовала бы второго адреса;
  вопрос снят, пока реализация одна.

**Открыто:**

- **Возврат MetalLB.** Проверить свободен ли адрес под пул и как поведёт себя policy-routing
  tailnet с LoadBalancer-IP. Изменение способа публикации адреса — риск для удалённого доступа.
- **Бюджет памяти.** Крупнейший потребитель — `longhorn instance-manager` (2.3 GiB), на одной
  ноде распределённое хранилище выгоды не даёт. Освобождение места — предусловие для переезда
  на Envoy Gateway (7ter.2), а не следствие.
- **Эквивалент `burst` для rate limit.** У Envoy Gateway в CRD только `limit.requests` +
  `limit.unit`; счётчик per-route. Ближайший эквивалент `burst: 50` не верифицирован — нужен
  эксперимент на живом data plane.
- **Fактическое потребление** Envoy Gateway, N42 Gateway и NGINX Gateway Fabric на этом узле:
  у них в основном нет дефолтов, поэтому единственный честный способ — поставить и снять
  `kubectl top`. Эталон для сравнения: Traefik на 48 маршрутах занимает 91Mi фактически.
- **Порядок с #672 (смена домена).** Домен теперь литералом в ~50 файлах вместо одного
  `values.yaml`. Миграция Gateway API завершена, решение об ordering не принималось.

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
- Дополнение 2026-10-01: даты релизов Gateway API (`v0.1.0` 2020-11-18, `v1.0.0` 2023-10-31,
  `v1.6.2` 2026-09-03) и EndpointSlice (K8s 1.17 — 2019-12-09, 1.21 — 2021-04-08) — через
  `api.github.com/repos/kubernetes-sigs/gateway-api/releases` и `/repos/kubernetes/kubernetes/releases/tags/`.
  Наличие версий API в тегах — по `api.github.com/repos/kubernetes/kubernetes/contents/staging/src/k8s.io/api/discovery`.

**Ресурсные дефолты (дополнение 2026-10-01):**
- Envoy Gateway: `charts/gateway-helm/values.yaml:64-69` (control plane); data plane и
  shutdown-manager — `api/v1alpha1/shared_types.go:25,27,32,34` — в tag v1.9.2.
- Traefik: `values.yaml:1227` (`resources: {}`) в chart 41.4.0.
- NGINX Gateway Fabric: `charts/nginx-gateway-fabric/values.yaml:223,810` в tag v2.7.2.
- N42 Gateway: `charts/haproxy-ingress/values.yaml:266,432` (v0.16.2),
  `charts/n42-gateway/values.yaml:284,450,521,614` (v0.17.0-alpha.3).
- Kong: `values.yaml:809,630,474` (chart `kong` 2.37.0, содержит KIC 3.5.x).
- Contour: `examples/contour/03-contour.yaml`, `03-envoy.yaml` (блоков resources нет).
- Istio: `manifests/charts/istio-control/istio-discovery/values.yaml:21-24`,
  `manifests/charts/gateway/values.yaml:75-81` в tag 1.31.0.
- Cilium: `install/kubernetes/cilium/values.yaml:337` в tag v1.20.2.
- kgateway: `install/helm/kgateway/values.yaml:39,86` в tag v2.4.5.
- Higress: `helm/core/values.yaml:529,648,683` в tag v2.2.4.
- ingress-nginx: `charts/ingress-nginx/values.yaml:397-403` в tag controller-v1.15.1.
- haproxytech/kubernetes-ingress: `deploy/haproxy-ingress.yaml:168-172` в tag v3.2.15.

**Измерения на кластере (2026-10-01):**
- `kubectl top pod -n traefik --containers` → Traefik 8m CPU / 91Mi RAM на 48 маршрутах.
- `kubectl get deploy -n traefik -o jsonpath` → requests 192Mi, limits 384Mi.
- `kubectl top node` → 21.9 GiB из 26.1 GiB allocatable (84%), 16 ядер, 4.1 в использовании.
- Сумма requests всех подов кластера — 23.2 GiB.

**Миграция на Gateway API:**
- ADR: `docs/adr/0010-gateway-api-routing.md`. Issue #700, PR #701–#706.
