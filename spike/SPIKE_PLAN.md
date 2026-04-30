# Spike — DSL renderer iOS + Android

## Objectif unique

Répondre à **une seule question** en 2 semaines : *un JSON DSL rendu par un shell natif produit-il une app indissociable d'une app SwiftUI/Compose codée à la main ?*

**Si OUI** → on continue le chantier plateforme (cf `docs/platform.md`).
**Si NON** → on revoit le pari technique avant d'investir plus.

## Contexte

Le design plateforme repose sur une hypothèse centrale : **90%+ des modules sont 100% server-driven**. Un module = backend Python + DSL JSON décrivant les écrans → rendu par le shell mobile natif. Si cette hypothèse ne tient pas (rendu cheap, dev ergonomics insupportables, parité iOS/Android impossible), **toute l'architecture s'effondre**.

Avant d'investir 6+ mois sur la plateforme, ce spike valide ou tue cette hypothèse.

## Périmètre

### Dans le scope

- **2 écrans, 2 plateformes** :
  - **Feed** : header + liste verticale de cards (titre + image + extrait + date)
  - **Détail** : ouvert au tap sur une card, header avec image, body markdown, bouton retour
- Navigation entre les deux (push)
- DSL hardcodé dans le bundle (un fichier JSON par écran), pas de CF, pas de Firebase
- Données = un fichier JSON statique de 10 articles avec `{title, excerpt, imageUrl, body, date}`
- Pull-to-refresh fonctionnel (même si refresh = no-op)
- Light mode + dark mode
- Dynamic Type (accessibilité texte)

### Hors scope

- Auth, capabilities, manifest validation
- Modules, marketplace, multi-tenant
- Cloud Functions, Firebase
- Form fields, primitives spécifiques (`map`, `calendar`, `segmented`)
- Cross-module extensions
- Build pipeline par commune
- Dashboard
- Emulator local pour devs

## Primitives DSL testées

Le strict minimum pour valider la mécanique. Si ces 10% ne marchent pas, le reste ne marchera pas.

| Primitive | Test |
|---|---|
| `scroll`, `vstack`, `hstack` | Layout du feed et du détail |
| `header` | Hauteur ajustable, image de fond, titre |
| `card` | Apparence native, ripple Android, highlight iOS |
| `image` | Loading async, placeholder, dark mode |
| `text`, `markdown` | Typographie native, Dynamic Type |
| `for` | Iteration sur le tableau d'articles |
| `if` | Conditionnel (ex: badge "nouveau" si date < 7j) |
| `{{ data binding }}` | Templating Mustache-like |
| `action: navigate` | Push depuis card → détail |

## Implémentation

- **Greenfield** : pas de framework tiers (Hyperview, etc.). Un parser JSON → SwiftUI views d'un côté, → Composables de l'autre. Code de spike, pas code de prod.
- Stack iOS : SwiftUI (iOS 16+ minimum)
- Stack Android : Jetpack Compose (Android API 26+ minimum)
- Solo dev — un dev iOS d'abord, puis Android (ou en alternance) pour s'assurer que la même DSL produit deux rendus cohérents

## Critères de succès / d'échec

### Verdict positif si **les 4** sont vrais

1. **Visuel natif** : un utilisateur lambda à qui on montre l'app du spike et une app SwiftUI/Compose hand-coded ne fait pas la différence. Animations, scroll, typographie, dark mode, Dynamic Type — tout est natif.
2. **Performance** : 60 fps au scroll, cold start < 2s, pas de jank au push entre écrans.
3. **Vélocité dev** : éditer le JSON et voir le changement à l'écran en < 30s (build incrémental).
4. **Parité iOS/Android** : la même DSL produit deux écrans qui se ressemblent assez pour qu'un screenshot des deux côte à côte donne le même flow visuel (pas pixel-perfect — cohérent).

### Verdict négatif (et donc reset du chantier) si

- Il faut beaucoup de "magic strings" dans le code natif pour gérer chaque cas
- Les animations ne se font pas naturellement et il faut les implémenter à la main pour chaque transition
- iOS et Android divergent tellement qu'il faut deux DSL différents
- La performance est sentie comme dégradée par rapport à du natif hand-coded

## Risques connus à anticiper

- **Animations de navigation** : SwiftUI `NavigationStack` et Compose `NavHost` ont des défauts qui ne sont pas dans le DSL — vérifier qu'on les obtient gratos
- **Markdown rendering** : iOS `AttributedString` natif depuis iOS 15, Android `compose-markdown` / `Markwon` — qualité variable, à benchmarker
- **Image cache** : `AsyncImage` SwiftUI vs Coil Compose — comportements différents au scroll rapide
- **Dark mode parity** : couleurs déclarées en JSON doivent réagir au système, pas hardcodées

## Budget temps

**2 semaines max**, solo dev. Si dépassement, c'est un signal d'échec : la complexité du renderer dépasse ce qu'un dev peut tenir, donc l'écosystème de modules ne tiendra jamais.

## Livrables

- 2 binaires runnable (TestFlight / APK) sur device réel
- Code des deux apps + le DSL dans `spike/ios/`, `spike/android/`, `spike/dsl-samples/`
- **`SPIKE_VERDICT.md`** rempli à la fin : réponse explicite aux 4 critères, surprises rencontrées, verdict GO / NO-GO
- **Liste enrichie de primitives** : ce qu'on a découvert qu'il fallait ajouter / retirer / nuancer (alimente `docs/platform.md`)
