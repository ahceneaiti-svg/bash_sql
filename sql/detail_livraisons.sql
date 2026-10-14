-- Détail des livraisons ; {{IDS}} est remplacé par la liste d'id
SELECT l.id, l.commande_id, l.transporteur, l.statut, l.date_expedition, cl.nom, cl.pays
FROM livraison l
JOIN commande c ON c.id = l.commande_id
LEFT JOIN client cl ON cl.id = c.client_id
WHERE l.id IN ({{IDS}});
