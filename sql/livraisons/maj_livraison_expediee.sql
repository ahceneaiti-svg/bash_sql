-- Passe les livraisons à EXPEDIE avec la date du jour ; {{IDS}} est remplacé par la liste d'id
UPDATE livraison
SET statut = 'EXPEDIE',
    date_expedition = CURDATE()
WHERE id IN ({{IDS}});
