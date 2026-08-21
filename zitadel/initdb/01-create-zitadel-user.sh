#!/bin/bash
set -euo pipefail

# Создаёт непривилегированную роль для ZITADEL и отдаёт ей базу.
# Выполняется entrypoint'ом postgres только на пустом каталоге данных.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	CREATE ROLE ${POSTGRES_ZITADEL_USER:-zitadel} LOGIN PASSWORD '${POSTGRES_ZITADEL_PASSWORD}';
	ALTER DATABASE ${POSTGRES_DB} OWNER TO ${POSTGRES_ZITADEL_USER:-zitadel};
EOSQL
