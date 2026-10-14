-- Passe les commandes à OK ; {{IDS}} est remplacé par la liste d'id (ex. 4,9,15)
UPDATE commande
SET statut = 'OK'
WHERE id IN ({{IDS}});
