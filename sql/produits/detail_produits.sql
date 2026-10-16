-- Détail des produits ; {{IDS}} est remplacé par la liste d'id
SELECT id, nom, categorie, prix, stock
FROM produit
WHERE id IN ({{IDS}});
