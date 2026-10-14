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

CREATE TABLE commande (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    statut     VARCHAR(20)   NOT NULL,
    client_id  INT           NOT NULL,
    date       DATE          NOT NULL,
    prix       DECIMAL(10,2) NOT NULL,
    produit_id INT           NOT NULL,
    CONSTRAINT fk_commande_client FOREIGN KEY (client_id) REFERENCES client (id)
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
