#!/usr/bin/env bash
# Script générique : parcourt les dossiers de $SQL_DIR (un dossier = un job). Pour chaque dossier,
# il se connecte à la base, exécute la requête SELECT, construit la liste d'id (1re colonne du résultat),
# exécute la requête UPDATE sur cette liste et journalise le tout. Toute la logique métier est dans les .sql.
#
# Usage : select_update.sh [dossier ...]
#   sans argument : tous les sous-dossiers de $SQL_DIR, dans l'ordre alphabétique
#   dossier       : nom d'un sous-dossier de $SQL_DIR (ex. commandes) pour ne lancer que ce job
# Convention de nommage dans un dossier :
#   maj_*.sql     : requête de mise à jour (obligatoire), le marqueur {{IDS}} est remplacé par la liste d'id
#   detail_*.sql  : requête de détail (optionnelle), même marqueur, loggée avant/après la mise à jour
#   autre *.sql   : requête de détection (obligatoire), 1re colonne = id
set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
DB_NAME="${DB_NAME:-ecommerce}"
LOG_DIR="${LOG_DIR:-/logs}"
RETENTION_JOURS="${RETENTION_JOURS:-7}"
SQL_DIR="${SQL_DIR:-/usr/local/share/sql}"

mkdir -p "$LOG_DIR"
# Un seul fichier de log par jour pour tous les jobs ; chaque lancement y ajoute un bloc horodaté (heure:minute)
LOG_FILE="$LOG_DIR/sql_updates_$(date '+%Y-%m-%d').log"
HEURE=$(date '+%H:%M')
ids=""

run_sql() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -B -e "$1" 2>/dev/null
}

run_sql_file() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -N -B < "$1" 2>/dev/null
}

# Lit un fichier .sql et remplace {{IDS}} par la liste d'id (valeurs issues de la base)
render_sql() {
    sed "s/{{IDS}}/$ids/g" "$1"
}

log() { echo "$*" | tee -a "$LOG_FILE"; }

# Liste les fichiers .sql d'un dossier selon le préfixe : $1 = dossier, $2 = maj | detail | select
list_sql() {
    local f base
    for f in "$1"/*.sql; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        case "$2:$base" in
            maj:maj_*|detail:detail_*) echo "$f" ;;
            select:maj_*|select:detail_*) ;;
            select:*) echo "$f" ;;
        esac
    done
}

# Exécute un job : $1 = nom du dossier dans $SQL_DIR
run_job() {
    local job="$1" dir="$SQL_DIR/$1" select_files update_files detail_files
    local select_f update_f detail_f="" rows update_sql

    select_files=$(list_sql "$dir" select)
    update_files=$(list_sql "$dir" maj)
    detail_files=$(list_sql "$dir" detail)

    if [ "$(echo -n "$select_files" | grep -c .)" -ne 1 ] || [ "$(echo -n "$update_files" | grep -c .)" -ne 1 ] \
        || [ "$(echo -n "$detail_files" | grep -c .)" -gt 1 ]; then
        log "[${job}] Dossier ignoré : il faut exactement 1 select, 1 maj_*.sql et au plus 1 detail_*.sql."
        log ""
        return 0
    fi
    select_f="$select_files"
    update_f="$update_files"
    detail_f="$detail_files"

    log "[${job}] Fichiers SQL : select=${select_f#"$SQL_DIR"/} | update=${update_f#"$SQL_DIR"/} | detail=$([ -n "$detail_f" ] && echo "${detail_f#"$SQL_DIR"/}" || echo aucun)"

    # 1. Sélection
    ids=""
    rows=$(run_sql_file "$select_f")
    if [ -z "$rows" ]; then
        log "[${job}] Aucune ligne détectée par ${select_f#"$SQL_DIR"/}."
        log ""
        return 0
    fi

    # 2. Construction de la liste d'id : 4,7,9,... (1re colonne)
    ids=$(echo "$rows" | awk '{print $1}' | paste -sd, -)

    log "--- Lignes détectées (${select_f#"$SQL_DIR"/}) ---"
    log "$rows"
    log "--- Liste des id ---"
    log "$ids"
    if [ -n "$detail_f" ]; then
        log "--- Détail avant mise à jour (${detail_f#"$SQL_DIR"/}) ---"
        log "$(run_sql "$(render_sql "$detail_f")")"
    fi

    # 3. Mise à jour
    update_sql=$(render_sql "$update_f")
    log "--- Requête exécutée (${update_f#"$SQL_DIR"/}) ---"
    log "$(echo "$update_sql" | grep -v '^--')"
    run_sql "$update_sql"

    # 4. Lignes mises à jour
    if [ -n "$detail_f" ]; then
        log "--- Détail après mise à jour (${detail_f#"$SQL_DIR"/}) ---"
        log "$(run_sql "$(render_sql "$detail_f")")"
    fi
    log ""
}

# Attente que la base accepte les connexions
for _ in $(seq 1 30); do
    run_sql "SELECT 1;" >/dev/null 2>&1 && break
    sleep 2
done

log "=== Lancement à ${HEURE} ($(date '+%F')) ==="

# Rétention : suppression des logs plus vieux que RETENTION_JOURS jours
purges=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'sql_updates_*.log' \
    -mmin +$((RETENTION_JOURS * 1440)) -print -delete)
if [ -n "$purges" ]; then
    log "--- Logs supprimés (rétention ${RETENTION_JOURS} jours) ---"
    log "$purges"
fi

# Jobs : dossiers passés en argument, sinon tous les sous-dossiers de $SQL_DIR
if [ "$#" -gt 0 ]; then
    jobs=("$@")
else
    jobs=()
    for d in "$SQL_DIR"/*/; do
        [ -d "$d" ] && jobs+=("$(basename "$d")")
    done
fi

if [ "${#jobs[@]}" -eq 0 ]; then
    log "Aucun dossier de requêtes dans ${SQL_DIR}."
    log ""
    exit 0
fi

for job in "${jobs[@]}"; do
    if [ ! -d "$SQL_DIR/$job" ]; then
        log "[${job}] Dossier introuvable dans ${SQL_DIR}."
        log ""
        continue
    fi
    run_job "$job"
done
