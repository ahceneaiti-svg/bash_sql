#!/usr/bin/env bash
# Script générique : se connecte à la base, exécute une requête SELECT, construit
# la liste d'id (1re colonne du résultat), exécute une requête UPDATE sur cette liste
# et journalise le tout. Toute la logique métier est dans les fichiers .sql.
#
# Usage : select_update.sh [select.sql [update.sql [detail.sql]]]
#   select.sql : requête de détection, 1re colonne = id
#   update.sql : requête de mise à jour, le marqueur {{IDS}} est remplacé par la liste d'id
#   detail.sql : (optionnel) requête de détail, même marqueur, loggée avant/après la mise à jour
# Un nom sans "/" est cherché dans $SQL_DIR.
set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
DB_NAME="${DB_NAME:-ecommerce}"
LOG_DIR="${LOG_DIR:-/logs}"
RETENTION_JOURS="${RETENTION_JOURS:-7}"
SQL_DIR="${SQL_DIR:-/usr/local/share/sql}"

SELECT_SQL="${1:-${SELECT_SQL:-commandes_abandonnees_france.sql}}"
UPDATE_SQL="${2:-${UPDATE_SQL:-maj_statut_ok.sql}}"
DETAIL_SQL="${3:-${DETAIL_SQL-detail_commandes.sql}}"

mkdir -p "$LOG_DIR"
# Un seul fichier de log par jour pour tous les jobs ; chaque lancement y ajoute un bloc horodaté (heure:minute)
LOG_FILE="$LOG_DIR/maj_commandes_$(date '+%Y-%m-%d').log"
HEURE=$(date '+%H:%M')
ids=""

sql_path() {
    case "$1" in
        */*) echo "$1" ;;
        *)   echo "$SQL_DIR/$1" ;;
    esac
}

run_sql() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -B -e "$1" 2>/dev/null
}

run_sql_file() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -B < "$(sql_path "$1")" 2>/dev/null
}

# Lit un fichier .sql et remplace {{IDS}} par la liste d'id (valeurs issues de la base)
render_sql() {
    sed "s/{{IDS}}/$ids/g" "$(sql_path "$1")"
}

log() { echo "$*" | tee -a "$LOG_FILE"; }

# Attente que la base accepte les connexions
for _ in $(seq 1 30); do
    run_sql "SELECT 1;" >/dev/null 2>&1 && break
    sleep 2
done

log "=== Lancement à ${HEURE} ($(date '+%F')) ==="
log "Fichiers SQL : select=${SELECT_SQL} | update=${UPDATE_SQL} | detail=${DETAIL_SQL:-aucun}"

# Rétention : suppression des logs plus vieux que RETENTION_JOURS jours
purges=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'maj_commandes_*.log' \
    -mmin +$((RETENTION_JOURS * 1440)) -print -delete)
if [ -n "$purges" ]; then
    log "--- Logs supprimés (rétention ${RETENTION_JOURS} jours) ---"
    log "$purges"
fi

# 1. Sélection
rows=$(run_sql_file "$SELECT_SQL")

if [ -z "$rows" ]; then
    log "Aucune ligne détectée par ${SELECT_SQL}."
    log ""
    exit 0
fi

# 2. Construction de la liste d'id : 4,7,9,... (1re colonne)
ids=$(echo "$rows" | awk '{print $1}' | paste -sd, -)

log "--- Lignes détectées (${SELECT_SQL}) ---"
log "$rows"
log "--- Liste des id ---"
log "$ids"
if [ -n "$DETAIL_SQL" ]; then
    log "--- Détail avant mise à jour (${DETAIL_SQL}) ---"
    log "$(run_sql "$(render_sql "$DETAIL_SQL")")"
fi

# 3. Mise à jour
update_sql=$(render_sql "$UPDATE_SQL")
log "--- Requête exécutée (${UPDATE_SQL}) ---"
log "$(echo "$update_sql" | grep -v '^--')"
run_sql "$update_sql"

# 4. Lignes mises à jour
if [ -n "$DETAIL_SQL" ]; then
    log "--- Détail après mise à jour (${DETAIL_SQL}) ---"
    log "$(run_sql "$(render_sql "$DETAIL_SQL")")"
fi
log ""
