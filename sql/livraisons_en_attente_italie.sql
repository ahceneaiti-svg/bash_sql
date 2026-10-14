-- Livraisons EN_ATTENTE des commandes de clients italiens
SELECT l.id, l.statut, cl.pays
FROM livraison l
JOIN commande c ON c.id = l.commande_id
LEFT JOIN client cl ON cl.id = c.client_id
WHERE l.statut = 'EN_ATTENTE'
  AND cl.pays = 'Italie';
