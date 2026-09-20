# Tailscale

Tailscale устанавливается непосредственно на Fedora-хост и предоставляет:

- SSH к серверу без белого IPv4 и проброса портов;
- доступ к сервисам на `<node1-ip>`;
- доступ к остальным устройствам домашней сети через subnet route
  `<node1-lan-cidr>`.

Tailscale SSH намеренно не включён: поверх tailnet используется уже настроенный
OpenSSH сервера.

## Подключение сервера

На сервере из корня репозитория выполнить:

```sh
sudo bash apps/tailscale/setup.sh
```

Команда выведет ссылку для входа. После авторизации открыть страницу
[Machines](https://login.tailscale.com/admin/machines), выбрать `homelab`, затем
в разделе **Subnets** одобрить маршрут `<node1-lan-cidr>` и снять одобрение
устаревших маршрутов (например, оставшейся от старой сети `<old-lan-cidr>`):
клиенты ходят в домашнюю сеть только через одобренные маршруты, и расхождение
с реальной LAN выглядит как «дома всё работает, удалённо — нет».

Чтобы сервер не терял маршрут после истечения ключа, там же рекомендуется
отключить key expiry для `homelab`.

Клиенты macOS, Windows, Android и iOS принимают subnet routes автоматически. На
Linux-клиенте это нужно включить отдельно:

```sh
sudo tailscale set --accept-routes
```

## Локальные DNS-имена

Чтобы через Tailscale продолжали работать адреса вида `dns.example.com`,
в [DNS-настройках tailnet](https://login.tailscale.com/admin/dns) нужен
restricted nameserver (split DNS):

- domain: `example.com`;
- nameserver: `<node1-ip>`.

Запросы этой зоны пойдут в домашний Technitium DNS через одобренный subnet
route, а прочие DNS-запросы останутся у обычного резолвера клиента.

В том же разделе проверить, что не осталось записей от старой конфигурации:
restricted nameserver на старый домен (`example.net`) и на старую
подсеть (`<node1-ip>`) нужно удалить — иначе каждый узел tailnet при
проверке таких резолверов получает предупреждение «Tailscale can't reach the
configured DNS servers» в `tailscale status`.

Сам сервер Tailscale-настройки DNS не принимает (`--accept-dns=false`):
он сам является DNS-сервером для зоны `${DOMAIN}`.

## Проверка

На удалённом клиенте с запущенным Tailscale:

```sh
tailscale ping homelab
ssh artlab@homelab
dig +short uptime.example.com A   # ожидается <node1-ip>
curl -I https://dns.example.com/
```

Ожидается ответ Tailscale ping, SSH-подключение, ответ DNS и HTTP redirect
`302` от Technitium.

Если внутренние имена не резолвятся только вне домашней сети:

1. В admin console (DNS) есть restricted nameserver `example.com →
   <node1-ip>`, а устаревшие записи удалены.
2. В admin console (Machines → homelab → Subnets) одобрен именно
   `<node1-lan-cidr>` — та подсеть, где реально живёт сервер.
3. На клиенте `tailscale ping homelab` проходит, а `dig` до появления записи
   возвращал NXDOMAIN — значит запрос уходил в публичный DNS.

Если сам `homelab` доступен, но адреса `<node1-lan-ip>` не открываются, сначала
проверить, что subnet route одобрен в admin console. Для firewalld может также
понадобиться masquerading в активной зоне хоста:

```sh
sudo firewall-cmd --permanent --zone=FedoraServer --add-masquerade
sudo firewall-cmd --reload
```

Не добавлять это правило без необходимости.
