#!/bin/bash
# Crée DB_USER (avec tous les droits sur DB_NAME) quand ce n'est pas root.
# Exécuté une seule fois, à l'initialisation du volume de données, après init.sql.
set -euo pipefail

DB_USER="${DB_USER:-root}"
[ "$DB_USER" = "root" ] && exit 0

mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
