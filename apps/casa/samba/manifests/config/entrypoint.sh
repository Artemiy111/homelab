#!/bin/sh
# Точка входа smbd. Учётки создаются повторно: у initContainer'а и у
# контейнера с smbd своя файловая система, /etc/passwd initContainer'а в
# основной контейнер не попадает.
set -eu

/scripts/ensure-users.sh
exec smbd -F --no-process-group --configfile=/etc/samba/smb.conf
