# MySQL e-commerce : conteneur, données et script de mise à jour

Conteneur MySQL 8.4 avec une base `ecommerce`, quatre tables liées (`client`, `produit`, `commande`, `livraison`) pré-remplies, et un script bash, exécuté par un **CronJob Kubernetes**, qui met à jour les données selon des requêtes SQL (ex. passe au statut `OK` les commandes `ABONDONNE` des clients de France).

Répartition : docker compose ne fait tourner que le **serveur MySQL** ; le script et les requêtes s'exécutent dans le CronJob (image `ahceneaiti/bash_cj:1.1`). Tout ce qui concerne Kubernetes est dans [`k8s/README.md`](k8s/README.md).

## Démarrage rapide

```bash
cp .env.example .env                                # adapter les identifiants
docker compose up -d --build                        # serveur MySQL (port 3306)
kind create cluster --name sql-updates              # cluster Kubernetes local
# renseigner DB_HOST dans k8s/configmap.yaml (passerelle du réseau docker "kind"), puis :
kubectl apply -f k8s/namespace.yaml -f k8s/configmap.yaml
kubectl -n sql-updates create secret generic sql-updates-db --from-env-file=.env
kubectl apply -f k8s/cronjob.yaml
k8s/run-job.sh                                      # lancer les jobs tout de suite (ou : k8s/run-job.sh livraisons)
```

Détails, explications et dépannage : `k8s/README.md`.

## Contenu

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image `mysql:8.4` + `init.sql` (serveur MySQL uniquement) |
| `docker-compose.yml` | Service `mysql` (port 3306, healthcheck) |
| `.env.example` | Modèle de configuration (utilisateur, mot de passe, base) : lu par docker compose et par le secret Kubernetes |
| `init_user.sh` | Crée `DB_USER` s’il n’est pas `root` |
| `sql/<domaine>/*.sql` | Un dossier par job : requête de détection, `maj_*.sql`, `detail_*.sql` (voir section 4) |
| `init.sql` | Création de la base, des tables `client`, `produit`, `commande`, `livraison` et du jeu de données |
| `select_update.sh` | Script générique, lancé par le CronJob : parcourt les dossiers sql/, exécute un SELECT puis un UPDATE sur la liste d'id obtenue pour chacun, écrit les logs |
| `Dockerfile.cronjob` | Image du CronJob `ahceneaiti/bash_cj:1.1` (busybox + bash + client mysql + script + `sql/`) |
| `k8s/` | Manifestes Kubernetes (`namespace`, `configmap`, `cronjob`, `job-manuel`), script `run-job.sh` et [README](k8s/README.md) |

## Prérequis

- Docker et Docker Compose v2 (`docker compose`)
- Port `3306` libre sur la machine
- Pour le CronJob (voir `k8s/README.md`) : `kubectl`, `kind`, `python3` (pour `k8s/run-job.sh`) et un accès à Docker Hub
- Un fichier `.env` (optionnel) : `cp .env.example .env` puis adapter les valeurs (voir « Fichier `.env` » en section 4)

## 1. Lancer le conteneur

```bash
docker compose up -d --build
```

Attendre que le conteneur soit `healthy` :

```bash
docker compose ps
```

Le conteneur `ecommerce-mysql` publie le port `3306` sur l'hôte : c'est ce port que le CronJob Kubernetes utilise pour se connecter.

Arrêter (les données sont conservées dans le conteneur/volume) :

```bash
docker compose down
```

## 2. Générer les données

Le jeu de données est créé automatiquement par `init.sql` **au premier démarrage** (base vide) : 10 clients, 10 produits, 15 commandes et 10 livraisons.

Clients : 6 en `France`, 4 en `Italie`.

Commandes (statut / pays du client) :

| Statut | France | Italie | Total |
|---|---|---|---|
| `TERMINE` | 6 | 0 | 6 |
| `EN_COURS` | 1 | 3 | 4 |
| `ABONDONNE` | 3 | 2 | 5 |

Produits : 10 références (id 101 à 110), dont 3 en stock faible (< 10) : 103, 106, 109.

Livraisons (une par commande en cours ou terminée) : 6 `LIVRE` et 4 `EN_ATTENTE` (3 pour des clients italiens, 1 pour un client français).

Table `client` :

| Colonne | Type |
|---|---|
| `id` | INT, auto-incrément, clé primaire |
| `nom` | VARCHAR(50) |
| `prenom` | VARCHAR(50) |
| `pays` | VARCHAR(30) : `France` ou `Italie` |
| `adresse` | VARCHAR(150) |

Table `produit` :

| Colonne | Type |
|---|---|
| `id` | INT, clé primaire (101 à 110) |
| `nom` | VARCHAR(80) |
| `categorie` | VARCHAR(40) |
| `prix` | DECIMAL(10,2) |
| `stock` | INT |

Table `commande` :

| Colonne | Type |
|---|---|
| `id` | INT, auto-incrément, clé primaire |
| `statut` | VARCHAR(20) : `TERMINE`, `EN_COURS`, `ABONDONNE` (puis `OK` après le script) |
| `client_id` | INT, clé étrangère vers `client.id` |
| `date` | DATE |
| `prix` | DECIMAL(10,2) |
| `produit_id` | INT, clé étrangère vers `produit.id` |

Table `livraison` :

| Colonne | Type |
|---|---|
| `id` | INT, auto-incrément, clé primaire |
| `commande_id` | INT, clé étrangère vers `commande.id` |
| `transporteur` | VARCHAR(40) |
| `statut` | VARCHAR(20) : `LIVRE`, `EN_ATTENTE` (puis `EXPEDIE` après le job livraisons) |
| `date_expedition` | DATE, nullable |

Table `historique` (alimentée automatiquement par des triggers `AFTER UPDATE` sur `client`, `produit`, `commande` et `livraison`) :

| Colonne | Type |
|---|---|
| `id` | BIGINT, auto-incrément, clé primaire |
| `nom_table` | VARCHAR(40) : table modifiée |
| `date_maj` | DATETIME : date de la mise à jour |
| `valeurs_avant` | JSON : toutes les colonnes de la ligne avant la mise à jour |
| `valeurs_apres` | JSON : toutes les colonnes de la ligne après la mise à jour |

Exemple : `SELECT nom_table, date_maj, valeurs_avant, valeurs_apres FROM historique ORDER BY id DESC;`

### Régénérer les données depuis zéro

`init.sql` ne s'exécute que sur une base vide. Pour repartir de l'état initial (par exemple après avoir lancé le script) :

```bash
docker compose down -v      # supprime le conteneur ET les données
docker compose up -d --build
```

Pour un autre jeu de données, modifier les `INSERT` de `init.sql` puis refaire les deux commandes ci-dessus.

## 3. Se connecter à la base

Identifiants : ceux de `.env` (`DB_USER`, `DB_PASSWORD`, `DB_NAME`). Sans `.env` : utilisateur `root`, mot de passe `root`, base `ecommerce`. Les exemples ci-dessous utilisent ces valeurs par défaut.

Depuis le conteneur :

```bash
docker compose exec mysql mysql -uroot -proot ecommerce
```

Depuis la machine hôte (client `mysql` installé) :

```bash
mysql -h 127.0.0.1 -P 3306 -uroot -proot ecommerce
```

Requête rapide sans session interactive :

```bash
docker compose exec mysql mysql -uroot -proot ecommerce \
  -e "SELECT cl.pays, c.statut, COUNT(*) FROM commande c JOIN client cl ON cl.id = c.client_id GROUP BY cl.pays, c.statut;"
```

## 4. Lancer le script (CronJob Kubernetes)

Le script est lancé par le CronJob `sql-updates` (toutes les heures pleines de 6h à 22h, voir `k8s/README.md`). Pour un lancement immédiat, hors planification :

```bash
k8s/run-job.sh                  # tous les jobs
k8s/run-job.sh livraisons       # un seul job
k8s/run-job.sh commandes produits
```

`k8s/run-job.sh` crée un Job à partir du CronJob, attend sa fin, affiche les logs puis le supprime. Un Job unique prêt à l'emploi existe aussi : `k8s/job-manuel.yaml` (voir `k8s/README.md`).

Le script est **générique** : il ne contient aucune requête métier ni aucun nom de fichier SQL. Il parcourt les sous-dossiers de `/usr/local/share/sql` (dossier `sql/` du projet, copié dans l'image) dans l'ordre alphabétique. **Un dossier = un job** : pour chacun il exécute le `SELECT`, construit la liste d'id à partir de la 1re colonne du résultat, exécute l'`UPDATE` sur cette liste et journalise le tout.

```
select_update.sh [-j|--job dossier] [dossier ...]
```

| Argument | Rôle |
|---|---|
| (aucun) | tous les sous-dossiers de `sql/`, un par un |
| `-j dossier`, `--job dossier` | ne lance que ce job (option répétable) |
| `dossier` | équivalent à `--job dossier` (forme positionnelle) |
| `-h`, `--help` | affiche l'aide |

Code retour : `0` si tout s'est bien passé, `1` si un job demandé n'existe pas (le Job Kubernetes échoue), `2` pour une option invalide.

Les fichiers d'un dossier sont repérés par leur préfixe :

| Fichier | Rôle |
|---|---|
| `maj_*.sql` | requête de mise à jour (obligatoire, un seul), `{{IDS}}` est remplacé par la liste d'id |
| `detail_*.sql` | requête de détail (optionnelle, un seul), même marqueur, loggée avant et après l'update |
| tout autre `*.sql` | requête de détection (obligatoire, un seul), la 1re colonne doit être l'`id` |

Un dossier qui ne respecte pas cette convention est ignoré avec un message dans le log. Le dossier `sql/` se change avec `SQL_DIR`.

### Jobs fournis (dossier `sql/`)

| Job (dossier) | select | update | detail |
|---|---|---|---|
| `commandes` : commandes abandonnées de France → `OK` | `commandes_abandonnees_france.sql` | `maj_statut_ok.sql` | `detail_commandes.sql` |
| `livraisons` : livraisons en attente d'Italie → `EXPEDIE` (date du jour) | `livraisons_en_attente_italie.sql` | `maj_livraison_expediee.sql` | `detail_livraisons.sql` |
| `produits` : stock faible (< 10) → réappro +50 | `produits_stock_faible.sql` | `maj_reappro_stock.sql` | `detail_produits.sql` |

Le CronJob planifié lance tous les jobs (aucun argument). L'argument optionnel `--job` permet d'en lancer un seul : `k8s/run-job.sh livraisons`, ou directement `select_update.sh --job livraisons` dans un conteneur.

Pour ajouter un job : créer un dossier `sql/<domaine>/` avec ses fichiers, puis reconstruire et pousser l'image avec un nouveau tag, et mettre à jour `image:` dans `k8s/cronjob.yaml` (voir `k8s/README.md`). Il est pris en compte automatiquement, sans modifier le script.

Exemple de sortie pour le job `commandes` (identique au contenu ajouté au log) :

```
=== Lancement à 19:50 (2026-10-14) ===
[commandes] Fichiers SQL : select=commandes/commandes_abandonnees_france.sql | update=commandes/maj_statut_ok.sql | detail=commandes/detail_commandes.sql
--- Lignes détectées (commandes/commandes_abandonnees_france.sql) ---
4	ABONDONNE	France
9	ABONDONNE	France
15	ABONDONNE	France
--- Liste des id ---
4,9,15
--- Détail avant mise à jour (commandes/detail_commandes.sql) ---
4	ABONDONNE	4	2026-02-10	89.99	104	France
...
--- Requête exécutée (commandes/maj_statut_ok.sql) ---
UPDATE commande
SET statut = 'OK'
WHERE id IN (4,9,15);
--- Détail après mise à jour (commandes/detail_commandes.sql) ---
4	OK	4	2026-02-10	89.99	104	France
...
```

Si un job ne détecte aucune ligne, le log contient `[dossier] Aucune ligne détectée par ...` et rien n'est modifié ; le script passe au dossier suivant.

### Fichier `.env`

Un fichier `.env` à la racine (non versionné) sert à `docker-compose.yml` (serveur MySQL) et à créer le secret Kubernetes du CronJob. Point de départ :

```bash
cp .env.example .env    # puis adapter DB_USER, DB_PASSWORD, DB_NAME
```

Si `DB_USER` n'est pas `root`, `init_user.sh` crée l'utilisateur avec tous les droits sur `DB_NAME` ; le mot de passe `root` du serveur reste `DB_PASSWORD`. Changer ces valeurs après la 1re initialisation demande de recréer le volume de données (`docker compose down -v`).

### Variables d'environnement (optionnelles)

| Variable | Défaut |
|---|---|
| `DB_HOST` | `localhost` (le ConfigMap Kubernetes le fixe) |
| `DB_PORT` | `3306` |
| `DB_USER` | `root` |
| `DB_PASSWORD` | `root` |
| `DB_NAME` | `ecommerce` |
| `LOG_DIR` | `/logs` (dans le pod, un `emptyDir` jetable) |
| `SQL_DIR` | `/usr/local/share/sql` (dossier contenant les sous-dossiers de jobs) |
| `RETENTION_JOURS` | `7` |

## 5. Logs

Le script écrit tout sur la sortie standard **et** dans `sql_updates_<AAAA-MM-JJ>.log` (un fichier par jour, commun à tous les jobs). Dans Kubernetes, ce fichier est dans un `emptyDir` détruit avec le pod : la lecture se fait par `kubectl logs`, et la rétention est celle des jobs conservés par le CronJob (3 réussis, 3 échoués).

```bash
kubectl -n sql-updates get jobs
kubectl -n sql-updates logs job/<nom-du-job>
```

Chaque lancement (tous les jobs) produit un bloc commençant par `=== Lancement à HH:MM (date) ===`, suivi de :

- les lignes détectées par le `SELECT` ;
- la liste des id ;
- le détail avant mise à jour (requête de détail) ;
- la requête `UPDATE` exécutée ;
- les lignes mises à jour, avec le même détail.

Le bloc contient une section par job (dossier), préfixée `[dossier]`. Si un job ne détecte aucune ligne, sa section se limite à `Aucune ligne détectée`.

`RETENTION_JOURS` (défaut 7, ConfigMap) pilote la suppression des anciens `sql_updates_*.log` dans `LOG_DIR` ; elle ne sert que si `LOG_DIR` est un volume persistant.

## 6. Déploiement Kubernetes (CronJob)

Le CronJob remplace l'ancien `crontab` de l'hôte (qui appelait `docker compose exec`, supprimé). Il se connecte au MySQL de docker compose par le réseau (`DB_HOST`/`DB_PORT`).

Image `ahceneaiti/bash_cj:1.1` : base `busybox:1.36-musl` + bash + client mysql + `select_update.sh` + `sql/`, `ENTRYPOINT` = `select_update.sh` (sans argument : tous les jobs).

Construction du cluster, ConfigMap, Secret, CronJob, test et dépannage : voir **[k8s/README.md](k8s/README.md)**.

## Notes

- Le fichier `.env` contient le mot de passe : il est ignoré par git, seul `.env.example` est versionné. Les valeurs par défaut (`root`/`root`) conviennent pour un test local uniquement.
- Le statut `ABONDONNE` est écrit tel quel (et non `ABANDONNE`) pour rester cohérent avec les données et le script.
