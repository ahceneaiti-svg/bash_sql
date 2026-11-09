# Déploiement Kubernetes : CronJob `sql-updates`

Le script `select_update.sh` et les requêtes `sql/` tournent dans un **CronJob** Kubernetes. MySQL reste dans docker compose (conteneur `ecommerce-mysql`, port `3306` publié sur l'hôte) : les pods s'y connectent par le réseau.

```
cluster kind "sql-updates"                      hôte docker
┌──────────────────────────┐   172.18.0.1:3306  ┌──────────────────────┐
│ CronJob sql-updates      │ ─────────────────▶ │ ecommerce-mysql      │
│  └ Job/Pod bash_cj:1.0   │                    │ (docker compose)     │
└──────────────────────────┘                    └──────────────────────┘
```

## Fichiers

| Fichier | Rôle |
|---|---|
| `namespace.yaml` | Namespace `sql-updates` |
| `configmap.yaml` | Configuration non secrète : `DB_HOST`, `DB_PORT`, `DB_NAME`, `RETENTION_JOURS` |
| `cronjob.yaml` | CronJob `0 6-22 * * *` (Europe/Paris), `concurrencyPolicy: Forbid`, image `ahceneaiti/bash_cj:1.0` |
| *(secret)* | `sql-updates-db` : `DB_USER` et `DB_PASSWORD`, **non versionné**, créé depuis `.env` |

Le secret est lu par le CronJob (`secretKeyRef`), la configuration par `envFrom` du ConfigMap.

## Prérequis

- `docker`, `kubectl`, `kind`
- Un fichier `.env` à la racine du projet (`cp .env.example .env`)
- Accès à Docker Hub (`docker login`) pour pousser l'image

## 1. Lancer MySQL

Depuis la racine du projet :

```bash
docker compose up -d --build
docker compose ps          # attendre "healthy"
```

## 2. Construire et pousser l'image

Base `busybox:1.36-musl` ; un stage `alpine` installe `bash`, `mariadb-client` et `mariadb-connector-c` (plugin `caching_sha2_password`, requis par MySQL 8.4), copiés ensuite sur busybox.

```bash
docker build -f Dockerfile.cronjob -t ahceneaiti/bash_cj:1.0 .
docker push ahceneaiti/bash_cj:1.0
```

Après modification du script ou de `sql/`, utiliser un **nouveau tag** (`1.1`, ...) et mettre à jour `image:` dans `cronjob.yaml` : avec `imagePullPolicy: IfNotPresent`, un tag réutilisé ne serait pas retiré par les nœuds.

## 3. Construire le cluster

```bash
kind create cluster --name sql-updates
kubectl config use-context kind-sql-updates
kubectl get nodes          # le nœud doit être Ready
```

## 4. Configurer `DB_HOST`

Les pods atteignent MySQL via la passerelle du réseau docker `kind` :

```bash
docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}'
```

Reporter l'adresse IPv4 (ex. `172.18.0.1`) dans `configmap.yaml` (`DB_HOST`). Avec minikube (driver docker) : `host.minikube.internal`. Le pare-feu de l'hôte doit laisser passer le port `3306`.

## 5. Déployer

Depuis la racine du projet :

```bash
kubectl apply -f k8s/namespace.yaml -f k8s/configmap.yaml

# Secret : DB_USER et DB_PASSWORD (+ autres clés du .env, ignorées par le CronJob)
kubectl -n sql-updates create secret generic sql-updates-db --from-env-file=.env \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/cronjob.yaml
kubectl -n sql-updates get cronjob      # SCHEDULE 0 6-22 * * *, TIMEZONE Europe/Paris
```

Changer le mot de passe : modifier `.env`, relancer la commande du secret. Les prochains pods lisent la nouvelle valeur. Changer le ConfigMap : `kubectl apply -f k8s/configmap.yaml` (pris en compte au prochain lancement).

## 6. Tester sans attendre l'horaire

```bash
kubectl -n sql-updates create job --from=cronjob/sql-updates test-1
kubectl -n sql-updates wait --for=condition=complete job/test-1 --timeout=120s
kubectl -n sql-updates logs job/test-1
kubectl -n sql-updates delete job test-1
```

Un seul job SQL (ex. `livraisons`), en passant le dossier en argument :

```bash
kubectl -n sql-updates create job test-2 --from=cronjob/sql-updates --dry-run=client -o json \
  | python3 -c 'import json,sys; j=json.load(sys.stdin); j["spec"]["template"]["spec"]["containers"][0]["args"]=["livraisons"]; print(json.dumps(j))' \
  | kubectl apply -f -
```

## 7. Exploitation

| Action | Commande |
|---|---|
| Voir les exécutions | `kubectl -n sql-updates get jobs,pods` |
| Logs d'une exécution | `kubectl -n sql-updates logs job/<nom>` |
| Suspendre | `kubectl -n sql-updates patch cronjob sql-updates -p '{"spec":{"suspend":true}}'` |
| Reprendre | `kubectl -n sql-updates patch cronjob sql-updates -p '{"spec":{"suspend":false}}'` |

Les logs sont sur stdout. Le fichier `sql_updates_*.log` du pod est dans un `emptyDir` détruit avec le pod : la rétention réelle est celle des jobs gardés (`successfulJobsHistoryLimit: 3`, `failedJobsHistoryLimit: 3`).

## Dépannage

| Symptôme | Cause probable |
|---|---|
| Pod `Completed` sans mise à jour, log s'arrête après `Fichiers SQL : ...` | Connexion MySQL refusée (erreurs masquées par le script) : vérifier `DB_HOST`, le port `3306`, les identifiants du secret |
| Log : `Plugin caching_sha2_password could not be loaded` | Image sans `mariadb-connector-c` |
| `ImagePullBackOff` | Image absente de Docker Hub ou tag incorrect dans `cronjob.yaml` |
| Aucune exécution à l'heure prévue | CronJob suspendu, ou horaire en `Europe/Paris` (`timeZone` du CronJob) |

Shell de débogage dans un pod (puis `mysql -h <DB_HOST> -u<user> -p<mdp> ecommerce`) :

```bash
kubectl -n sql-updates run -it --rm dbg --image=ahceneaiti/bash_cj:1.0 --restart=Never --command -- sh
```

## Supprimer

```bash
kubectl delete namespace sql-updates     # CronJob, ConfigMap, Secret
kind delete cluster --name sql-updates
docker compose down
```
