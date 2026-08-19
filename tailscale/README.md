# Tailscale

Tailscale устанавливается непосредственно на Fedora-хост и предоставляет:

- SSH к серверу без белого IPv4 и проброса портов;
- доступ к сервисам на `192.0.2.10`;
- доступ к остальным устройствам домашней сети через subnet route
  `192.0.2.10/24`.

Tailscale SSH намеренно не включён: поверх tailnet используется уже настроенный
OpenSSH сервера.

## Подключение сервера

На сервере из корня репозитория выполнить:

```sh
sudo bash tailscale/setup.sh
```

Команда выведет ссылку для входа. После авторизации открыть страницу
[Machines](https://login.tailscale.com/admin/machines), выбрать `homelab`, затем
в разделе **Subnets** одобрить маршрут `192.0.2.10/24`.

Чтобы сервер не терял маршрут после истечения ключа, там же рекомендуется
отключить key expiry для `homelab`.

Клиенты macOS, Windows, Android и iOS принимают subnet routes автоматически. На
Linux-клиенте это нужно включить отдельно:

```sh
sudo tailscale set --accept-routes
```

## Локальные DNS-имена

Чтобы через Tailscale продолжали работать адреса вида
`pihole.example.com`, в [DNS-настройках tailnet](https://login.tailscale.com/admin/dns)
добавить restricted nameserver:

- nameserver: `192.0.2.10`;
- domain: `example.com`.

Запросы этой зоны пойдут в домашний Pi-hole, а прочие DNS-запросы останутся у
обычного резолвера клиента.

## Проверка

На удалённом клиенте с запущенным Tailscale:

```sh
tailscale ping homelab
ssh artlab@homelab
curl -I https://pihole.example.com/admin/
```

Ожидается ответ Tailscale ping, SSH-подключение и HTTP redirect `302` от Pi-hole.

Если сам `homelab` доступен, но адреса `192.168.3.x` не открываются, сначала
проверить, что subnet route одобрен в admin console. Для firewalld может также
понадобиться masquerading в активной зоне хоста:

```sh
sudo firewall-cmd --permanent --zone=FedoraServer --add-masquerade
sudo firewall-cmd --reload
```

Не добавлять это правило без необходимости.
