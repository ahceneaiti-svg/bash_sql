# MySQL e-commerce : conteneur, données et script de mise à jour

Conteneur MySQL 8.4 avec une base `ecommerce`, quatre tables liées (`client`, `produit`, `commande`, `livraison`) pré-remplies, et un script bash qui passe au statut `OK` les commandes `ABONDONNE` des clients de France.

## Contenu

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image `mysql:8.4` + `init.sql` + script bash |
| `docker-compose.yml` | Service `mysql` (port 3306, healthcheck, volume `./logs`) |
| `.env.example` | Modèle de configuration (utilisateur, mot de passe, base, dossier de logs) |
| `init_user.sh` | Crée `DB_USER` s’il n’est pas `root` |
| `sql/<domaine>/*.sql` | Un dossier par job : requête de détection, `maj_*.sql`, `detail_*.sql` (voir section 4) |
| `init.sql` | Création de la base, des tables `client`, `produit`, `commande`, `livraison` et du jeu de données |
| `select_update.sh` | Script générique : parcourt les dossiers sql/, exécute un SELECT puis un UPDATE sur la liste d'id obtenue pour chacun, écrit les logs |
| `logs/` | Fichiers de logs générés par le script |

## Prérequis

- Docker et Docker Compose v2 (`docker compose`)
- Port `3306` libre sur la machine
- Un fichier `.env` (optionnel) : `cp .env.example .env` puis adapter les valeurs (voir « Fichier `.env` » en section 4)

## 1. Lancer le conteneur

```bash
docker compose up -d --build
```

Attendre que le conteneur soit `healthy` :

```bash
docker compose ps
```

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

## 4. Lancer le script bash

```bash
docker compose exec mysql select_update.sh
```

Le script est **générique** : il ne contient aucune requête métier ni aucun nom de fichier SQL. Il parcourt les sous-dossiers de `/usr/local/share/sql` (dossier `sql/` du projet, copié dans l'image) dans l'ordre alphabétique. **Un dossier = un job** : pour chacun il exécute le `SELECT`, construit la liste d'id à partir de la 1re colonne du résultat, exécute l'`UPDATE` sur cette liste et journalise le tout.

```
select_update.sh [dossier ...]
```

| Argument | Rôle |
|---|---|
| (aucun) | tous les sous-dossiers de `sql/`, un par un |
| `dossier` | un ou plusieurs noms de sous-dossier (ex. `commandes`) pour ne lancer que ces jobs |

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

```bash
docker compose exec mysql select_update.sh                # tous les jobs
docker compose exec mysql select_update.sh livraisons     # un seul job
```

Pour ajouter un job : créer un dossier `sql/<domaine>/` avec ses fichiers, puis rebuild (`docker compose up -d --build`). Il est pris en compte automatiquement, sans modifier le script.

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

`docker-compose.yml` lit un fichier `.env` à la racine (non versionné). Point de départ :

```bash
cp .env.example .env    # puis adapter DB_USER, DB_PASSWORD, DB_NAME, LOG_DIR
```

`LOG_DIR` est le dossier des logs côté hôte (monté sur `/logs` dans le conteneur). Si `DB_USER` n'est pas `root`, `init_user.sh` crée l'utilisateur avec tous les droits sur `DB_NAME` ; le mot de passe `root` du serveur reste `DB_PASSWORD`. Changer ces valeurs après la 1re initialisation demande de recréer le volume de données (`docker compose down -v`).

### Variables d'environnement (optionnelles)

| Variable | Défaut |
|---|---|
| `DB_HOST` | `localhost` |
| `DB_USER` | `root` |
| `DB_PASSWORD` | `root` |
| `DB_NAME` | `ecommerce` |
| `LOG_DIR` | `/logs` (dans le conteneur ; `docker-compose.yml` le fixe, le `LOG_DIR` du `.env` désigne le dossier hôte) |
| `SQL_DIR` | `/usr/local/share/sql` (dossier contenant les sous-dossiers de jobs) |
| `RETENTION_JOURS` | `7` |

## 5. Logs

Un seul fichier de log par jour dans `./logs/` par défaut, ou dans le dossier `LOG_DIR` du `.env` (dossier monté sur `/logs` dans le conteneur) : `sql_updates_<AAAA-MM-JJ>.log`, commun à tous les jobs.

Chaque lancement du script (tous les jobs) **ajoute un bloc** commençant par `=== Lancement à HH:MM (date) ===` (heure et minute du lancement), suivi de :

- les lignes détectées par le `SELECT` ;
- la liste des id ;
- le détail avant mise à jour (requête de détail) ;
- la requête `UPDATE` exécutée ;
- les lignes mises à jour, avec le même détail.

Le bloc contient une section par job (dossier), préfixée `[dossier]`. Si un job ne détecte aucune ligne, sa section se limite à `Aucune ligne détectée`.

```bash
ls logs/
cat logs/sql_updates_*.log
```

### Rétention et nettoyage

À chaque lancement, avant le traitement, le script supprime les fichiers `sql_updates_*.log` plus vieux que `RETENTION_JOURS` jours (7 par défaut, soit 7 × 24 h depuis leur dernière modification). Les fichiers supprimés sont listés dans le bloc du lancement (`--- Logs supprimés ---`). Les autres fichiers du dossier ne sont jamais touchés.

Changer la durée : `docker compose exec -e RETENTION_JOURS=30 mysql select_update.sh` (ponctuel), ou `environment:` dans `docker-compose.yml` pour le cron.

Les fichiers de `logs/` sont créés par le conteneur (propriétaire root) et ignorés par git. Pour les supprimer :

```bash
docker compose exec mysql sh -c 'rm -f /logs/*.log'
```

## 6. Exécution automatique (crontab)

Le fichier `crontab` lance le script toutes les heures pleines de 6h à 22h (6:00, 7:00, ... 22:00, soit 17 exécutions par jour) :

```
0 6-22 * * * cd /home/aia/workspace/claude/bash_sql && /usr/bin/docker compose exec -T mysql select_update.sh >/dev/null 2>&1
```

Le cron s'exécute sur la machine hôte et appelle le script dans le conteneur, qui doit donc être démarré (`docker compose up -d`). Adapter le chemin du projet dans `crontab` si besoin.

```bash
crontab crontab     # installe (ATTENTION : remplace le crontab existant de l'utilisateur)
crontab -l          # vérifie
crontab -r          # supprime le crontab de l'utilisateur
```

Chaque exécution ajoute un bloc dans le log du jour (voir section 5).

## Notes

- Le fichier `.env` contient le mot de passe : il est ignoré par git, seul `.env.example` est versionné. Les valeurs par défaut (`root`/`root`) conviennent pour un test local uniquement.
- Le statut `ABONDONNE` est écrit tel quel (et non `ABANDONNE`) pour rester cohérent avec les données et le script.
