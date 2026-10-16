-- Commandes abandonnées des clients français
SELECT c.id, c.statut, cl.pays
FROM commande c
LEFT JOIN client cl ON cl.id = c.client_id
WHERE c.statut = 'ABONDONNE'
  AND cl.pays = 'France';
