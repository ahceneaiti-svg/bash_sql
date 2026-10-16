CREATE DATABASE IF NOT EXISTS ecommerce CHARACTER SET utf8mb4;
USE ecommerce;

CREATE TABLE client (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    nom     VARCHAR(50)  NOT NULL,
    prenom  VARCHAR(50)  NOT NULL,
    pays    VARCHAR(30)  NOT NULL,
    adresse VARCHAR(150) NOT NULL
);

INSERT INTO client (nom, prenom, pays, adresse) VALUES
('Martin',   'Julie',    'France', '12 rue de la Paix, 75002 Paris'),
('Dubois',   'Pierre',   'France', '8 avenue Foch, 69006 Lyon'),
('Rossi',    'Marco',    'Italie', 'Via Roma 15, 00184 Roma'),
('Bernard',  'Sophie',   'France', '25 rue Nationale, 59800 Lille'),
('Lefebvre', 'Camille',  'France', '3 place Bellecour, 69002 Lyon'),
('Bianchi',  'Giulia',   'Italie', 'Corso Buenos Aires 40, 20124 Milano'),
('Moreau',   'Thomas',   'France', '17 cours Mirabeau, 13100 Aix-en-Provence'),
('Esposito', 'Luca',     'Italie', 'Via Toledo 100, 80134 Napoli'),
('Garnier',  'Emma',     'France', '5 quai des Chartrons, 33000 Bordeaux'),
('Romano',   'Francesca','Italie', 'Via Garibaldi 22, 10122 Torino');

CREATE TABLE produit (
    id        INT PRIMARY KEY,
    nom       VARCHAR(80)   NOT NULL,
    categorie VARCHAR(40)   NOT NULL,
    prix      DECIMAL(10,2) NOT NULL,
    stock     INT           NOT NULL
);

INSERT INTO produit (id, nom, categorie, prix, stock) VALUES
(101, 'Clavier mécanique',    'Informatique',  19.90,  42),
(102, 'Écran 27 pouces',      'Informatique', 120.00,  15),
(103, 'Souris sans fil',      'Informatique',  15.50,   4),
(104, 'Casque audio',         'Audio',         89.99,  25),
(105, 'Enceinte Bluetooth',   'Audio',         55.00,  30),
(106, 'Ordinateur portable',  'Informatique', 250.00,   2),
(107, 'Webcam HD',            'Informatique',  75.25,  18),
(108, 'Tablette graphique',   'Informatique', 310.00,  11),
(109, 'Câble HDMI',           'Accessoires',   42.00,   7),
(110, 'Support ordinateur',   'Accessoires',   12.99,  60);

CREATE TABLE commande (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    statut     VARCHAR(20)   NOT NULL,
    client_id  INT           NOT NULL,
    date       DATE          NOT NULL,
    prix       DECIMAL(10,2) NOT NULL,
    produit_id INT           NOT NULL,
    CONSTRAINT fk_commande_client FOREIGN KEY (client_id) REFERENCES client (id),
    CONSTRAINT fk_commande_produit FOREIGN KEY (produit_id) REFERENCES produit (id)
);

INSERT INTO commande (statut, client_id, date, prix, produit_id) VALUES
('TERMINE',   1, '2026-01-05',  49.90, 101),
('TERMINE',   2, '2026-01-12', 120.00, 102),
('EN_COURS',  3, '2026-02-03',  15.50, 103),
('ABONDONNE', 4, '2026-02-10',  89.99, 104),
('TERMINE',   5, '2026-02-18',  34.00, 105),
('EN_COURS',  1, '2026-03-01', 250.00, 106),
('ABONDONNE', 6, '2026-03-07',  19.90, 101),
('TERMINE',   7, '2026-03-15',  75.25, 107),
('ABONDONNE', 2, '2026-03-22', 310.00, 108),
('EN_COURS',  8, '2026-04-02',  42.00, 109),
('TERMINE',   9, '2026-04-09',  12.99, 110),
('ABONDONNE', 3, '2026-04-14',  64.50, 102),
('EN_COURS', 10, '2026-04-20', 199.99, 103),
('TERMINE',   4, '2026-05-01',  27.80, 104),
('ABONDONNE', 5, '2026-05-06',  55.00, 105);

CREATE TABLE livraison (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    commande_id     INT         NOT NULL,
    transporteur    VARCHAR(40) NOT NULL,
    statut          VARCHAR(20) NOT NULL,
    date_expedition DATE        NULL,
    CONSTRAINT fk_livraison_commande FOREIGN KEY (commande_id) REFERENCES commande (id)
);

INSERT INTO livraison (commande_id, transporteur, statut, date_expedition) VALUES
(1,  'Colissimo',      'LIVRE',      '2026-01-06'),
(2,  'Chronopost',     'LIVRE',      '2026-01-13'),
(3,  'Poste Italiane', 'EN_ATTENTE', NULL),
(5,  'Colissimo',      'LIVRE',      '2026-02-19'),
(6,  'Chronopost',     'EN_ATTENTE', NULL),
(8,  'BRT',            'LIVRE',      '2026-03-16'),
(10, 'BRT',            'EN_ATTENTE', NULL),
(11, 'Colissimo',      'LIVRE',      '2026-04-10'),
(13, 'Poste Italiane', 'EN_ATTENTE', NULL),
(14, 'DHL',            'LIVRE',      '2026-05-02');

-- Historique des modifications : un trigger AFTER UPDATE par table y écrit l'état de la ligne avant/après
CREATE TABLE historique (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    nom_table     VARCHAR(40) NOT NULL,
    date_maj      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valeurs_avant JSON        NOT NULL,
    valeurs_apres JSON        NOT NULL,
    INDEX idx_historique_table_date (nom_table, date_maj)
);

CREATE TRIGGER trg_client_maj AFTER UPDATE ON client FOR EACH ROW
INSERT INTO historique (nom_table, valeurs_avant, valeurs_apres) VALUES (
    'client',
    JSON_OBJECT('id', OLD.id, 'nom', OLD.nom, 'prenom', OLD.prenom, 'pays', OLD.pays, 'adresse', OLD.adresse),
    JSON_OBJECT('id', NEW.id, 'nom', NEW.nom, 'prenom', NEW.prenom, 'pays', NEW.pays, 'adresse', NEW.adresse)
);

CREATE TRIGGER trg_produit_maj AFTER UPDATE ON produit FOR EACH ROW
INSERT INTO historique (nom_table, valeurs_avant, valeurs_apres) VALUES (
    'produit',
    JSON_OBJECT('id', OLD.id, 'nom', OLD.nom, 'categorie', OLD.categorie, 'prix', OLD.prix, 'stock', OLD.stock),
    JSON_OBJECT('id', NEW.id, 'nom', NEW.nom, 'categorie', NEW.categorie, 'prix', NEW.prix, 'stock', NEW.stock)
);

CREATE TRIGGER trg_commande_maj AFTER UPDATE ON commande FOR EACH ROW
INSERT INTO historique (nom_table, valeurs_avant, valeurs_apres) VALUES (
    'commande',
    JSON_OBJECT('id', OLD.id, 'statut', OLD.statut, 'client_id', OLD.client_id, 'date', OLD.date, 'prix', OLD.prix, 'produit_id', OLD.produit_id),
    JSON_OBJECT('id', NEW.id, 'statut', NEW.statut, 'client_id', NEW.client_id, 'date', NEW.date, 'prix', NEW.prix, 'produit_id', NEW.produit_id)
);

CREATE TRIGGER trg_livraison_maj AFTER UPDATE ON livraison FOR EACH ROW
INSERT INTO historique (nom_table, valeurs_avant, valeurs_apres) VALUES (
    'livraison',
    JSON_OBJECT('id', OLD.id, 'commande_id', OLD.commande_id, 'transporteur', OLD.transporteur, 'statut', OLD.statut, 'date_expedition', OLD.date_expedition),
    JSON_OBJECT('id', NEW.id, 'commande_id', NEW.commande_id, 'transporteur', NEW.transporteur, 'statut', NEW.statut, 'date_expedition', NEW.date_expedition)
);
