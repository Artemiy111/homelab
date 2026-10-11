# Каталог подключаемых конфигов Samba.
#
# Дистрибутивный smb.conf не знает про smb.conf.d/ — это соглашение
# Samba, а не её поведение. Без строки `include` в [global] файлы
# здесь лежат и молча игнорируются.

# Секции шар и параметры производительности (см. homelab.conf).
include = /etc/samba/smb.conf.d/homelab.conf