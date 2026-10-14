#!/usr/bin/env bash
set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
DB_NAME="${DB_NAME:-ecommerce}"
LOG_DIR="${LOG_DIR:-/logs}"
RETENTION_JOURS="${RETENTION_JOURS:-7}"
SQL_DIR="${SQL_DIR:-/usr/local/share/sql}"

mkdir -p "$LOG_DIR"
# Un fichier par jour ; chaque lancement y ajoute un bloc horodaté (heure:minute)
LOG_FILE="$LOG_DIR/maj_commandes_$(date '+%Y-%m-%d').log"
HEURE=$(date '+%H:%M')

run_sql() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -B -e "$1" 2>/dev/null
}

run_sql_file() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -B < "$1" 2>/dev/null
}

log() { echo "$*" | tee -a "$LOG_FILE"; }

# Attente que MySQL accepte les connexions
for _ in $(seq 1 30); do
    run_sql "SELECT 1;" >/dev/null 2>&1 && break
    sleep 2
done

log "=== Lancement à ${HEURE} ($(date '+%F')) ==="

# Rétention : suppression des logs plus vieux que RETENTION_JOURS jours
purges=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'maj_commandes_*.log' \
    -mmin +$((RETENTION_JOURS * 1440)) -print -delete)
if [ -n "$purges" ]; then
    log "--- Logs supprimés (rétention ${RETENTION_JOURS} jours) ---"
    log "$purges"
fi

# 1. Sélection des commandes abandonnées
rows=$(run_sql_file "$SQL_DIR/commandes_abandonnees_france.sql")

if [ -z "$rows" ]; then
    log "Aucune commande ABONDONNE pour la France."
    log ""
    exit 0
fi

# 2. Construction de la liste d'id : 4,7,9,...
ids=$(echo "$rows" | awk '{print $1}' | paste -sd, -)

log "--- Commandes détectées (id, statut, pays) ---"
log "$rows"
log "--- Liste des id ---"
log "$ids"
log "--- Détail avant mise à jour (id, statut, client_id, date, prix, produit_id, pays) ---"
log "$(run_sql "SELECT c.id, c.statut, c.client_id, c.date, c.prix, c.produit_id, cl.pays FROM commande c LEFT JOIN client cl ON cl.id = c.client_id WHERE c.id IN ($ids);")"

# 3. Mise à jour
# {{IDS}} du fichier .sql est remplacé par la liste d'id (valeurs numériques issues de la base)
update_sql=$(sed "s/{{IDS}}/$ids/g" "$SQL_DIR/maj_statut_ok.sql")
log "--- Requête exécutée ---"
log "$(echo "$update_sql" | grep -v '^--')"
run_sql "$update_sql"

# 4. Lignes mises à jour
log "--- Lignes mises à jour (id, statut, client_id, date, prix, produit_id, pays) ---"
log "$(run_sql "SELECT c.id, c.statut, c.client_id, c.date, c.prix, c.produit_id, cl.pays FROM commande c LEFT JOIN client cl ON cl.id = c.client_id WHERE c.id IN ($ids);")"
log ""
