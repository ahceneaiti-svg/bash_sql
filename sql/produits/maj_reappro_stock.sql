-- Réapprovisionne de 50 unités ; {{IDS}} est remplacé par la liste d'id
UPDATE produit
SET stock = stock + 50
WHERE id IN ({{IDS}});
