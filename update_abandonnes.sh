#!/usr/bin/env bash
set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
DB_NAME="${DB_NAME:-ecommerce}"
LOG_DIR="${LOG_DIR:-/logs}"

mkdir -p "$LOG_DIR"
STAMP=$(date '+%Y%m%d_%H%M%S')
LOG_DETECTEES="$LOG_DIR/detectees_${STAMP}.log"
LOG_MAJ="$LOG_DIR/mises_a_jour_${STAMP}.log"

run_sql() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -B -e "$1"
}

# Attente que MySQL accepte les connexions
for _ in $(seq 1 30); do
    run_sql "SELECT 1;" >/dev/null 2>&1 && break
    sleep 2
done

# 1. Sélection des commandes abandonnées
rows=$(run_sql "SELECT id, statut FROM commande WHERE statut = 'ABONDONNE';")

if [ -z "$rows" ]; then
    echo "Aucune commande ABONDONNE."
    exit 0
fi

# Log 1 : liste détectée
{
    echo "# $(date '+%F %T') - commandes détectées (id, statut)"
    echo "$rows"
} | tee "$LOG_DETECTEES"

# 2. Construction de la liste d'id : 4,7,9,...
ids=$(echo "$rows" | awk '{print $1}' | paste -sd, -)
echo "Liste des id : $ids"

# 3. Mise à jour
run_sql "UPDATE commande SET statut = 'OK' WHERE id IN ($ids);"

# Log 2 : commandes à jour
{
    echo "# $(date '+%F %T') - commandes mises à jour (id, statut)"
    run_sql "SELECT id, statut FROM commande WHERE id IN ($ids);"
} | tee "$LOG_MAJ"
