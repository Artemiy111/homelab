# Tailscale

Tailscale устанавливается непосредственно на Fedora-хост и предоставляет:

- SSH к серверу без белого IPv4 и проброса портов;
- доступ к сервисам на `<node1-ip>`;
- доступ к остальным устройствам домашней сети через subnet route
  `<node1-lan-cidr>`.

Tailscale SSH намеренно не включён: поверх tailnet используется уже настроенный
OpenSSH сервера.

## Локальные DNS-имена

Чтобы через Tailscale продолжали работать адреса вида `dns.example.com`,
в [DNS-настройках tailnet](https://login.tailscale.com/admin/dns) нужен
restricted nameserver (split DNS):

- domain: `example.com`;
- nameserver: `<node1-ip>`.

Запросы этой зоны пойдут в домашний Technitium DNS через одобренный subnet
route, а прочие DNS-запросы останутся у обычного резолвера клиента.

Итоговое состояние описано кодом в `infra/casa/terraform/tailscale`
(`tailscale_dns_configuration`): правка в admin console перезапишется на
следующем `terraform apply`, а устаревшие записи чистит ресурс, а не рука.
Ручные шаги — в `RUNBOOK.md`.

В том же разделе проверить, что не осталось записей от старой конфигурации:
restricted nameserver на старый домен (`example.net`) и на старую
подсеть (`<node1-ip>`) нужно удалить — иначе каждый узел tailnet при
проверке таких резолверов получает предупреждение «Tailscale can't reach the
configured DNS servers» в `tailscale status`.

Сам сервер Tailscale-настройки DNS не принимает (`--accept-dns=false`):
он сам является DNS-сервером для зоны `${DOMAIN}`.
