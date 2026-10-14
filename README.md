# MySQL e-commerce : conteneur, données et script de mise à jour

Conteneur MySQL 8.4 avec une base `ecommerce`, deux tables liées (`client` et `commande`) pré-remplies, et un script bash qui passe au statut `OK` les commandes `ABONDONNE` des clients de France.

## Contenu

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image `mysql:8.4` + `init.sql` + script bash |
| `docker-compose.yml` | Service `mysql` (port 3306, healthcheck, volume `./logs`) |
| `init.sql` | Création de la base, des tables `client` et `commande` et du jeu de données |
| `update_abandonnes.sh` | Détecte les `ABONDONNE` des clients français, les passe à `OK`, écrit les logs |
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

Le jeu de données est créé automatiquement par `init.sql` **au premier démarrage** (base vide) : 10 clients et 15 commandes.

Clients : 6 en `France`, 4 en `Italie`.

Commandes (statut / pays du client) :

| Statut | France | Italie | Total |
|---|---|---|---|
| `TERMINE` | 6 | 0 | 6 |
| `EN_COURS` | 1 | 3 | 4 |
| `ABONDONNE` | 3 | 2 | 5 |

Table `client` :

| Colonne | Type |
|---|---|
| `id` | INT, auto-incrément, clé primaire |
| `nom` | VARCHAR(50) |
| `prenom` | VARCHAR(50) |
| `pays` | VARCHAR(30) : `France` ou `Italie` |
| `adresse` | VARCHAR(150) |

Table `commande` :

| Colonne | Type |
|---|---|
| `id` | INT, auto-incrément, clé primaire |
| `statut` | VARCHAR(20) : `TERMINE`, `EN_COURS`, `ABONDONNE` (puis `OK` après le script) |
| `client_id` | INT, clé étrangère vers `client.id` |
| `date` | DATE |
| `prix` | DECIMAL(10,2) |
| `produit_id` | INT |

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
docker compose exec mysql update_abandonnes.sh
```

Le script :

1. attend que MySQL accepte les connexions ;
2. exécute la requête suivante (seules les commandes de clients français sont retenues, les italiennes restent `ABONDONNE`) :
   ```sql
   SELECT c.id, c.statut, cl.pays
   FROM commande c LEFT JOIN client cl ON cl.id = c.client_id
   WHERE c.statut = 'ABONDONNE' AND cl.pays = 'France';
   ```
3. construit la liste d'id (ex. `4,9,15`) ;
4. exécute `UPDATE commande SET statut = 'OK' WHERE id IN (...)` ;
5. relit les lignes modifiées ;
6. écrit tout le détail dans le fichier de log du jour (voir section 5).

Sortie attendue (identique au contenu ajouté au log) :

```
=== Lancement à 19:50 (2026-10-14) ===
--- Commandes détectées (id, statut, pays) ---
4	ABONDONNE	France
9	ABONDONNE	France
15	ABONDONNE	France
--- Liste des id ---
4,9,15
--- Détail avant mise à jour (id, statut, client_id, date, prix, produit_id, pays) ---
4	ABONDONNE	4	2026-02-10	89.99	104	France
...
--- Requête exécutée ---
UPDATE commande SET statut = 'OK' WHERE id IN (4,9,15);
--- Lignes mises à jour (id, statut, client_id, date, prix, produit_id, pays) ---
4	OK	4	2026-02-10	89.99	104	France
...
```

S'il n'y a plus de commande `ABONDONNE` pour la France, le script affiche `Aucune commande ABONDONNE pour la France.` et ne modifie rien.

### Variables d'environnement (optionnelles)

| Variable | Défaut |
|---|---|
| `DB_HOST` | `localhost` |
| `DB_USER` | `root` |
| `MYSQL_ROOT_PASSWORD` | `root` |
| `DB_NAME` | `ecommerce` |
| `LOG_DIR` | `/logs` |
| `RETENTION_JOURS` | `7` |

## 5. Logs

Un seul fichier de log par jour dans `./logs/` (dossier monté sur `/logs` dans le conteneur) : `maj_commandes_<AAAA-MM-JJ>.log`.

Chaque lancement du script **ajoute un bloc** commençant par `=== Lancement à HH:MM (date) ===` (heure et minute du lancement), suivi de :

- les commandes détectées (id, statut, pays) ;
- la liste des id ;
- le détail des commandes avant mise à jour (id, statut, client_id, date, prix, produit_id, pays) ;
- la requête `UPDATE` exécutée ;
- les lignes mises à jour, avec le même détail.

Si aucune commande `ABONDONNE` française n'est trouvée, le bloc contient seulement l'en-tête et `Aucune commande ABONDONNE pour la France.`.

```bash
ls logs/
cat logs/maj_commandes_*.log
```

### Rétention et nettoyage

À chaque lancement, avant le traitement, le script supprime les fichiers `maj_commandes_*.log` plus vieux que `RETENTION_JOURS` jours (7 par défaut, soit 7 × 24 h depuis leur dernière modification). Les fichiers supprimés sont listés dans le bloc du lancement (`--- Logs supprimés ---`). Les autres fichiers du dossier ne sont jamais touchés.

Changer la durée : `docker compose exec -e RETENTION_JOURS=30 mysql update_abandonnes.sh` (ponctuel), ou `environment:` dans `docker-compose.yml` pour le cron.

Les fichiers de `logs/` sont créés par le conteneur (propriétaire root) et ignorés par git. Pour les supprimer :

```bash
docker compose exec mysql sh -c 'rm -f /logs/*.log'
```

## 6. Exécution automatique (crontab)

Le fichier `crontab` lance le script toutes les heures pleines de 6h à 22h (6:00, 7:00, ... 22:00, soit 17 exécutions par jour) :

```
0 6-22 * * * cd /home/aia/workspace/claude/bash_sql && /usr/bin/docker compose exec -T mysql update_abandonnes.sh >/dev/null 2>&1
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
