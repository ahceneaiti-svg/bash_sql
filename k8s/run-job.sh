#!/usr/bin/env bash
# Lance un job SQL à la demande depuis le CronJob, puis affiche ses logs.
# Usage : k8s/run-job.sh [dossier ...]   (sans argument : tous les jobs)
# Exemple : k8s/run-job.sh livraisons
set -euo pipefail

NS="${NS:-sql-updates}"
CRONJOB="${CRONJOB:-sql-updates}"
name="manuel-$(date +%s)"

args=()
for j in "$@"; do args+=(--job "$j"); done

# Copie le modèle du CronJob (image, env, secret) et ajoute les arguments au conteneur
kubectl -n "$NS" create job "$name" --from="cronjob/$CRONJOB" --dry-run=client -o json \
    | ARGS="$(printf '%s\n' "${args[@]+"${args[@]}"}")" python3 -c '
import json, os, sys
j = json.load(sys.stdin)
a = [x for x in os.environ["ARGS"].split("\n") if x]
if a:
    j["spec"]["template"]["spec"]["containers"][0]["args"] = a
print(json.dumps(j))' \
    | kubectl apply -f - >/dev/null

kubectl -n "$NS" wait --for=condition=complete "job/$name" --timeout=180s \
    || { kubectl -n "$NS" logs "job/$name" || true; exit 1; }
kubectl -n "$NS" logs "job/$name"
kubectl -n "$NS" delete "job/$name" >/dev/null
