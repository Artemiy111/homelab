# Troubleshoot: доступ к k8s-сервисам (gatus и др.) через Tailscale

Дата: 2026-08-31
Контекст: однонодный k0s, ingress-контроллер — Traefik в k8s, внешний IP выдаёт MetalLB.

> **Актуальность на 2026-09-15.** Запись оставлена как хроника разбора. MetalLB
> выведен 2026-09-14: вход кластера — `<node1-ip>` через `externalIPs` сервиса
> Traefik, VIP больше не используется (см. `platform/k0s/README.md`). Правило
> policy routing из раздела «Решение» при этом по-прежнему нужно: проблема
> обратного маршрута не зависит от способа выдачи входного адреса.

## Симптом

Pod gatus в k8s — `Running`, Service/Ingress на месте, но с ноутбука, находящегося
вне локальной сети (доступ только через Tailscale), не открывается ни один k8s-сервис
(`uptime.example.com` = gatus, а также `lute`, `home`, `kuma`).

В локальной сети сервера всё работает.

## Быстрый диагноз

- `ping <node1-ip>` (реальный IP ноды) через Tailscale — **отвечает**.
- `ping <node1-ip>` (VIP входа кластера, MetalLB) через Tailscale —
  `Destination Host Unreachable` от `<node1-ip>`.
- `curl` на хвостовой адрес ноды `198.51.100.11:443` — `connection refused`.

Вывод: дело не в gatus и не в локальном DNS/настройке ноутбука — у **всех** k8s-сервисов
общий вход (`<node1-vip>`), и до него через Tailscale не достучаться.

## Корень проблемы

MetalLB в L2/ARP-режиме выдаёт LoadBalancer-сервису виртуальный LAN-адрес (`<node1-vip>`).
Этот VIP обслуживается только в ARP-плоскости физической LAN (`enp2s0`):

- с **LAN** пакеты на `<node1-vip>` приходят на сетевой интерфейс, срабатывает ARP сервера
  и DNAT/kube-proxy — трафик попадает в Traefik pod;
- с **Tailscale** пакеты уже «внутри» хоста (приходят на `tailscale0`) — а Linux-ядро
  не имеет `<node1-vip>` как локального адреса и не слушает его там, поэтому шлёт
  `Destination Host Unreachable`.

Это свойство **устройства** LoadBalancer в L2-режиме, а не глюк: такой вход
не обслуживает не-LAN (tailscale) путь.

## Что пробовали (эксперимент) и чем закончилось

Гипотеза: «сделать `<node1-vip>` локальным адресом на tailscale-интерфейсе» — тогда ядро
примет трафик с tailscale.

На сервере (root):
```sh
sudo ip addr add <metallb-ip>/32 dev tailscale0
```

Результат:
- `<node1-vip>` появился на `tailscale0`;
- `ip route get <node1-ip>` → `local ... dev lo table local` — ядро перестало
  рассматривать `<node1-vip>` как вход LoadBalancer и начало слать пакеты в loopback;
- на `<node1-vip>:443` **нет слушателя** (`ss` показывает слушателей только на
  `<node1-ip>:443/80` и `:8443` — это Docker-Traefik);
- curl с ноутбука вместо `refused` стал просто **висеть** (пакеты уходят в loopback,
  там никто не слушает).

**Вывод эксперимента:** подход «сделать VIP локальным адресом» в корне неверен для
MetalLB L2. LoadBalancer в L2-режиме работает через ARP + DNAT на входе с LAN, а не
как процесс, слушающий `<node1-vip>:443`. Делая `<node1-vip>` локальным, мы ломаем механизм входа,
а не чиним его.

Откат (обязателен после теста):
```sh
sudo ip addr del <metallb-ip>/32 dev tailscale0
```
После отката проверить, что LAN-доступ к k8s-сервисам вернулся.

## Настоящая причина (2026-09-14)

Эксперимент с `<node1-vip>` на `tailscale0` был неверной гипотезой. Настоящая причина —
**policy routing Tailscale**: ответные пакеты LoadBalancer/NodePort к tailnet-клиенту
уходили через физический интерфейс вместо `tailscale0`.

`tcpdump -ni any` на ноде во время попытки `198.51.100.13 → <node1-ip>:443`:

```
cali4f9b7f7db7b In  10.244.107.177.8443 > <node1-ip>.15800: Flags [S.]   # SYN-ACK от пода
enp2s0        Out <node1-ip>.32610 > 198.51.100.13.59132: Flags [S.]     # уходит в LAN, не в туннель
```

Входящий путь полностью рабочий: SYN дошёл → kube-proxy DNAT в под → под ответил.
Ломается только маршрут обратного пакета.

Tailscale ставит правила:

```
0:    from all lookup local
5210: from all fwmark 0x80000/0xff0000 lookup main
5230: from all fwmark 0x80000/0xff0000 lookup default
5250: from all fwmark 0x80000/0xff0000 unreachable
5270: from all lookup 52
```

Форвардный ответ сервиса несёт метку `fwmark 0x80000`, поэтому матчится правило
**5210** — поиск в `main`, где для `198.51.100.13` есть только default
(`via <node1-ip> dev enp2s0`). Правило `5270: lookup 52` (таблица Tailscale с
маршрутом на `tailscale0`) стоит *после* fwmark-правил и не срабатывает.

## Решение

Правило с более высоким приоритетом, матчащееся по адресу назначения, а не по метке:

```sh
sudo ip rule add to 100.64.0.0/10 lookup 52 priority 5200
```

Проверено с удалённого tailnet-клиента: `nc <node1-ip> 32610` — succeeded,
`curl https://<node1-ip>/ -H 'Host: uptime.example.com'` — `200`, TLS —
валидный Let's Encrypt (`*.example.com`). LAN-доступ не затронут (пакеты к
`192.168.x` под правило не попадают).

Правило не переживает перезагрузку, поэтому закреплено systemd-юнитом
`etc/systemd/tailscale-policy-route.service` (ставится через `ansible/host.yml`).
Юнит идемпотентен и перезапускается вместе с `tailscaled` (`PartOf=`).

## Статус

- Решено через правило policy routing + systemd-юнит; оператор для этого не нужен.
- Tailscale Operator (`tailscale-operator`, `traefik-tailscale`) был установлен в
  рамках эксперимента, но после правки policy routing стал избыточен и **удалён**
  (helm uninstall + удаление `traefik-tailscale`). Узел `tailscale-operator` в
  tailnet остаётся офлайн-записью — убрать в admin console.
- Отдельно: `docs/research/k8s/remote-access-metallb-solutions.md` (Вариант 5, BGP)
  к этой задаче отношения не имеет.
