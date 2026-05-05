# Restaurants locaux

Module communautaire — annuaire des restaurants, bistrots, fritkots et cafés de la commune.

## Auteur

Slow Food Wallonie (asbl) — contributeur tiers.

## Licence

MIT.

## Capabilities

Aucune. Module purement bundlé : les données sont packagées dans `data/restaurants.json` (5 adresses exemple). Pas de Firestore, pas de CF.

## Adapter pour votre commune

1. Forker ce repo
2. Copier `modules-community/restos-locaux/` sous un nouvel id (ex. `modules-community/restos-<votre-commune>/`)
3. Éditer `manifest.json` (`id`, `displayName`, `author`)
4. Remplacer `data/restaurants.json` par vos adresses locales
5. Valider : `python3 tools/validate-manifests.py`
6. Soumettre une PR

## Structure

```
restos-locaux/
├── manifest.json        # contrat module (id, capabilities, screens)
├── screens/
│   ├── list.json        # liste des restaurants (cards)
│   └── detail.json      # détail d'un restaurant
└── data/
    └── restaurants.json # adresses bundlées
```

## Schéma d'une adresse

| Champ | Type | Description |
|---|---|---|
| `id` | string | Identifiant stable (slug court) |
| `name` | string | Nom de l'établissement |
| `cuisine` | string | Type de cuisine (libre) |
| `priceRange` | string | `€`, `€€`, `€€€` |
| `address` | string | Adresse postale |
| `hours` | string | Horaires multi-ligne |
| `phone` | string | Téléphone (format libre) |
| `logoUrl` | string | URL d'une photo représentative (16:10 ou 16:9 conseillé) |
| `description` | string | Texte libre, 1-3 phrases |
