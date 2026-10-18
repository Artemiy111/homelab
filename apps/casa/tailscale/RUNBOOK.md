# Tailscale: эксплуатация

## Подключение сервера

Скрипт ставит Tailscale на узел и читает файл репозитория
(`99-tailscale.conf`), поэтому запускается с контроллера (macOS): файлы
копируются во временный каталог на узле с сохранением раскладки `apps/casa/tailscale/`,
затем скрипт идёт под sudo.

```sh
ssh homelab 'mkdir -p /tmp/homelab-bootstrap/apps/casa/tailscale'
scp apps/casa/tailscale/setup.sh apps/casa/tailscale/99-tailscale.conf \
  homelab:/tmp/homelab-bootstrap/apps/casa/tailscale/
ssh -t homelab 'cd /tmp/homelab-bootstrap && LAN_CIDR=<node1-lan-cidr> sudo -E bash apps/casa/tailscale/setup.sh'
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

## Проверка

На удалённом клиенте с запущенным Tailscale:

```sh
tailscale ping homelab
ssh ops@homelab
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
