-- Détail des commandes ; {{IDS}} est remplacé par la liste d'id (ex. 4,9,15)
SELECT c.id, c.statut, c.client_id, c.date, c.prix, c.produit_id, cl.pays
FROM commande c
LEFT JOIN client cl ON cl.id = c.client_id
WHERE c.id IN ({{IDS}});
