# MySQL e-commerce : conteneur, données et script de mise à jour

Conteneur MySQL 8.4 avec une base `ecommerce`, quatre tables liées (`client`, `produit`, `commande`, `livraison`) pré-remplies, et un script bash qui passe au statut `OK` les commandes `ABONDONNE` des clients de France.

## Contenu

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image `mysql:8.4` + `init.sql` + script bash |
| `docker-compose.yml` | Service `mysql` (port 3306, healthcheck, volume `./logs`) |
| `sql/<domaine>/*.sql` | Requêtes SELECT / détail / UPDATE lues par le script (voir section 4, « Jobs fournis ») |
| `init.sql` | Création de la base, des tables `client`, `produit`, `commande`, `livraison` et du jeu de données |
| `select_update.sh` | Script générique : exécute un SELECT, puis un UPDATE sur la liste d'id obtenue, écrit les logs |
| `logs/` | Fichiers de logs générés par le script |

## Prérequis

- Docker et Docker Compose v2 (`docker compose`)
- Port `3306` libre sur la machine

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

### Régénérer les données depuis zéro

`init.sql` ne s'exécute que sur une base vide. Pour repartir de l'état initial (par exemple après avoir lancé le script) :

```bash
docker compose down -v      # supprime le conteneur ET les données
docker compose up -d --build
```

Pour un autre jeu de données, modifier les `INSERT` de `init.sql` puis refaire les deux commandes ci-dessus.

## 3. Se connecter à la base

Identifiants : utilisateur `root`, mot de passe `root`, base `ecommerce`.

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

Le script est **générique** : il ne contient aucune requête métier. Il se connecte à la base, exécute un fichier `SELECT`, construit la liste d'id à partir de la 1re colonne du résultat, exécute un fichier `UPDATE` sur cette liste et journalise le tout.

```
select_update.sh [select.sql [update.sql [detail.sql]]]
```

| Argument | Rôle | Défaut |
|---|---|---|
| `select.sql` | requête de détection, la 1re colonne doit être l'`id` | `commandes/commandes_abandonnees_france.sql` |
| `update.sql` | requête de mise à jour, `{{IDS}}` est remplacé par la liste d'id | `commandes/maj_statut_ok.sql` |
| `detail.sql` | (optionnel) requête de détail, même marqueur, loggée avant et après l'update | `commandes/detail_commandes.sql` |

Un chemin relatif (ex. `commandes/maj_statut_ok.sql`) est cherché dans `/usr/local/share/sql` (dossier `sql/` du projet, copié dans l'image). Un chemin absolu est utilisé tel quel. Les trois fichiers peuvent aussi être donnés par les variables `SELECT_SQL`, `UPDATE_SQL`, `DETAIL_SQL` ; `DETAIL_SQL=` (vide) désactive le détail.

Sans argument, le script traite les commandes `ABONDONNE` des clients français :

1. attend que MySQL accepte les connexions ;
2. exécute `sql/commandes/commandes_abandonnees_france.sql` (les commandes italiennes restent `ABONDONNE`) :
   ```sql
   SELECT c.id, c.statut, cl.pays
   FROM commande c LEFT JOIN client cl ON cl.id = c.client_id
   WHERE c.statut = 'ABONDONNE' AND cl.pays = 'France';
   ```
3. construit la liste d'id (ex. `4,9,15`) ;
4. exécute `sql/commandes/maj_statut_ok.sql` (`UPDATE commande SET statut = 'OK' WHERE id IN (...)`) ;
5. relit les lignes modifiées avec `sql/commandes/detail_commandes.sql` ;
6. écrit tout le détail dans le fichier de log du jour (voir section 5).

### Jobs fournis (dossier `sql/`)

Chaque job = un `SELECT` (1re colonne = id), un `UPDATE` avec `{{IDS}}` et un détail optionnel.

| Job | select | update | detail |
|---|---|---|---|
| Commandes abandonnées de France → `OK` (défaut, cron) | `commandes/commandes_abandonnees_france.sql` | `commandes/maj_statut_ok.sql` | `commandes/detail_commandes.sql` |
| Livraisons en attente d'Italie → `EXPEDIE` (date du jour) | `livraisons/livraisons_en_attente_italie.sql` | `livraisons/maj_livraison_expediee.sql` | `livraisons/detail_livraisons.sql` |
| Produits en stock faible (< 10) → réappro +50 | `produits/produits_stock_faible.sql` | `produits/maj_reappro_stock.sql` | `produits/detail_produits.sql` |

```bash
docker compose exec mysql select_update.sh livraisons/livraisons_en_attente_italie.sql livraisons/maj_livraison_expediee.sql livraisons/detail_livraisons.sql
docker compose exec mysql select_update.sh produits/produits_stock_faible.sql produits/maj_reappro_stock.sql produits/detail_produits.sql
```

Pour ajouter un job : créer les fichiers dans `sql/<domaine>/`, rebuild (`docker compose up -d --build`) et les passer en arguments.

Exemple avec d'autres requêtes :

```bash
docker compose exec mysql select_update.sh /chemin/select.sql /chemin/update.sql
```

Sortie attendue (identique au contenu ajouté au log) :

```
=== Lancement à 19:50 (2026-10-14) ===
Fichiers SQL : select=commandes/commandes_abandonnees_france.sql | update=commandes/maj_statut_ok.sql | detail=commandes/detail_commandes.sql
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

S'il n'y a plus de commande `ABONDONNE` pour la France, le script affiche `Aucune ligne détectée.` et ne modifie rien.

### Variables d'environnement (optionnelles)

| Variable | Défaut |
|---|---|
| `DB_HOST` | `localhost` |
| `DB_USER` | `root` |
| `MYSQL_ROOT_PASSWORD` | `root` |
| `DB_NAME` | `ecommerce` |
| `LOG_DIR` | `/logs` |
| `SQL_DIR` | `/usr/local/share/sql` |
| `SELECT_SQL` / `UPDATE_SQL` / `DETAIL_SQL` | voir tableau des arguments |
| `RETENTION_JOURS` | `7` |

## 5. Logs

Un seul fichier de log par jour dans `./logs/` (dossier monté sur `/logs` dans le conteneur) : `maj_commandes_<AAAA-MM-JJ>.log`, commun à tous les jobs.

Chaque lancement du script **ajoute un bloc** commençant par `=== Lancement à HH:MM (date) ===` (heure et minute du lancement), suivi de :

- les lignes détectées par le `SELECT` ;
- la liste des id ;
- le détail avant mise à jour (requête de détail) ;
- la requête `UPDATE` exécutée ;
- les lignes mises à jour, avec le même détail.

Si aucune commande `ABONDONNE` française n'est trouvée, le bloc contient seulement l'en-tête et `Aucune ligne détectée.`.

```bash
ls logs/
cat logs/maj_commandes_*.log
```

### Rétention et nettoyage

À chaque lancement, avant le traitement, le script supprime les fichiers `maj_commandes_*.log` plus vieux que `RETENTION_JOURS` jours (7 par défaut, soit 7 × 24 h depuis leur dernière modification). Les fichiers supprimés sont listés dans le bloc du lancement (`--- Logs supprimés ---`). Les autres fichiers du dossier ne sont jamais touchés.

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

- Le mot de passe `root` en clair dans `docker-compose.yml` convient pour un test local uniquement.
- Le statut `ABONDONNE` est écrit tel quel (et non `ABANDONNE`) pour rester cohérent avec les données et le script.
