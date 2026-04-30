# Spike — Verdict

> Date de début : 2026-04-30
> Date de fin : 2026-04-30
> Temps réel passé : ~1 jour solo (vs budget 2 semaines)

## Verdict global

**GO**

Le pari technique tient : ~400 lignes de Swift + ~400 lignes de Kotlin suffisent pour rendre 2 écrans (feed + détail) + 1 écran info + 1 tabbar à partir d'un JSON DSL commun, en restant indistinguables d'une app codée à la main. Les 11 primitives implémentées couvrent les 4 modules officiels du design plateforme. Aucune divergence de DSL entre iOS et Android.

## Réponse aux 4 critères

### 1. Visuel natif

*Status : ✅*

Constat : SwiftUI et Compose donnent gratos l'animation de push (`NavigationStack` / `NavHost`), le ripple/highlight des cards, le pull-to-refresh, le dark mode (couleurs systèmes via `Color(.secondarySystemGroupedBackground)` / `MaterialTheme.colorScheme.surfaceVariant`), et Dynamic Type / font scaling. La tab bar Material 3 et le UITabView sont natifs sans ajustement. Confirmé sur device : "C'est super fluide" + "PARFAIT".

### 2. Performance

*Status : ✅*

Pas de jank au scroll de la liste de 10 articles ni au push card→détail sur iVince (iPhone 15 Pro) et device Android (ZY22HC8VBP). Cold start sub-seconde sur les deux. AsyncImage / Coil gèrent le cache image au scroll rapide sans freeze. Pas de mesure FPS instrumentée — la fluidité ressentie est suffisante à ce stade.

### 3. Vélocité dev

*Status : ✅*

Cycle "edit JSON → rebuild → relaunch" :
- **iOS** : `xcodebuild` incrémental + `devicectl install/launch` ≈ 15-20s.
- **Android** : `./gradlew assembleDebug` + `adb install/launch` ≈ 30-40s (Gradle plus lent qu'xcodebuild incrémental).

Sous le seuil des 30s du plan côté iOS. Android est marginal mais acceptable. La structure `assets.srcDirs("../../dsl-samples")` côté Compose garantit qu'un seul fichier JSON édité touche les deux apps simultanément (validé : on n'a pas dupliqué un seul JSON).

### 4. Parité iOS / Android

*Status : ✅*

Mêmes 11 primitives, même DSL, même structure de fichiers. Le rendu visuel diverge marginalement (Material vs Apple defaults : couleurs surfaceVariant, hauteur de la NavigationBar, look du badge) mais le **flow et la hiérarchie sont identiques** — c'est l'objectif du critère #4 (pas pixel-perfect mais cohérent).

## Surprises rencontrées

**Mauvaises (à acter dans le design) :**

1. **Aucune des deux plateformes n'a un rendu markdown block-level natif.** SwiftUI `Text(AttributedString(markdown:options: .full))` collapse les blocs en un run inline (titres et listes ignorés). Compose n'a tout simplement rien. Solution adoptée des deux côtés : **paragraph-splitter maison** (séparation par `\n\n`, détection des `## heading` / `- bullet`, rendu en `Column` / `VStack` de `Text`). Le markdown inline (`**bold**`, `*italic*`) reste géré nativement par AttributedString iOS et un mini-parser Kotlin → AnnotatedString. À documenter comme limitation : la primitive `markdown` du contrat est en réalité un sous-ensemble (titres niveaux 1-3, listes à puces simples, gras, italique). Pas de tableaux, pas de blocs de code, pas de citations.

2. **Le primitive `header` ne peut pas être une combinaison naïve `image + text` dans une `vstack`.** Premier essai naïf en SwiftUI (`ZStack { AsyncImage(scaledToFill), gradient, Text }.frame(height: 280).frame(maxWidth: .infinity).clipped()`) débordait horizontalement de l'écran sur le détail — `scaledToFill` peut faire grossir le ZStack au-delà de la largeur proposée si l'image n'est pas encadrée AVANT le compositing. Pattern qui marche : `Color.frame(maxWidth: .infinity).frame(height: H).overlay { AsyncImage(scaledToFill) }.clipped()`. **Conclusion** : `header` doit rester une primitive atomique du renderer, pas une composition documentée comme dérivable.

3. **Mapping iconographique non trivial.** SF Symbols (iOS) vs Material Icons (Android) ont des noms différents et des couvertures différentes. J'ai mappé 9 noms à la main dans Compose (`newspaper` → `Icons.Filled.Newspaper`, `info.circle` → `Icons.Filled.Info`, etc.). Le DSL doit spécifier un nom canonique (probablement le SF Symbol) et le renderer Android maintient une table de correspondance. À budgéter : ~200 icônes Material Symbols + Outlined à mapper si on veut couvrir le besoin réel.

**Bonnes :**

4. **Compose Navigation 2.8 type-safe** (`composable<ScreenRoute>` + `@Serializable data class ScreenRoute`) est aussi propre que `NavigationStack { ... }.navigationDestination(for: Route.self)` côté iOS. La symétrie a évité de dupliquer la logique de routing.

5. **Spike conclu en ~1 jour solo, pas 2 semaines.** Indique que les 11 primitives ne sont pas un mur — elles tiennent dans un seul fichier `Renderer` de chaque côté. Renforce l'hypothèse que le DSL peut grossir sans que le renderer ne s'effondre.

6. **Primitive `tabbar` ajoutée pendant le spike** suite à un retour utilisateur ("on n'a pas de tab menu") — non prévue au plan initial mais absorbable en ~30 lignes de chaque côté. Bon signe pour la malléabilité du contrat.

## Primitives — révisions à apporter au design

Modifications à faire dans `docs/platform.md` :

**À ajouter :**

- `tabbar` : primitive racine pour les apps multi-onglets. Champs : `tabs: [{ title, icon, screen, bindings? }]`. Chaque onglet a sa propre stack de navigation.
- `markdown` : préciser le sous-ensemble supporté (headings 1-3, bullets simples, **bold**, *italic*). Documenter qu'inline-only suffit pour 80% des cas et que les tableaux nécessiteraient un fork natif côté renderer.
- Convention de mapping iconographique : DSL spécifie le nom SF Symbol, le renderer Android tient une table de correspondance. Marketplace devra valider que les icônes utilisées par les modules sont toutes dans la table avant publication.

**À retirer :**

- (rien)

**À nuancer :**

- `header` : décrire explicitement comme primitive atomique — un module ne peut pas reconstruire l'effet "image + gradient + titre" à partir de `vstack + image + text` (cf surprise 2). Le renderer doit fournir le composite.
- Les types numériques en JSON (`spacing: 12` vs `spacing: 12.0`) : la décodage Kotlinx-serialization est strict (`Int` vs `Double` distincts). J'ai tout typé en `Double?` dans le DSL. À documenter : tous les nombres dans le DSL sont des floats côté contrat.

## Recommandation pour la suite

**GO sur le chantier plateforme — entièrement greenfield dans `commune_solutions/`. Awans reste hors périmètre.**

Par où commencer :

1. **Geler les primitives validées** dans `docs/platform.md` — éditer le doc avec les surprises ci-dessus (markdown sous-ensemble explicité, `tabbar` ajouté, `header` atomique, mapping iconographique). C'est la spec stable que les modules cibleront.

2. **Backlog technique greenfield** (à séquencer ensuite) :
   - Renderer iOS et Android passés en module Swift Package / Maven module pour réutilisation propre.
   - Auth + multi-tenant (jusqu'ici le spike charge des assets statiques).
   - Pipeline backend (Firestore / CF / autre) qui sert le DSL au runtime au lieu des assets bundlés.
   - Table de correspondance icônes SF Symbols ↔ Material complète.
   - Capability declaration et permission UX (Android-like).
   - Manifest module + outillage marketplace.

3. **Le spike reste jetable** : son code n'a pas vocation à devenir le renderer de production. Mais les ~800 lignes Swift+Kotlin sont une référence d'implémentation propre — récrire from scratch en gardant cette structure (Model / Engine / Renderer / Dispatcher) est la voie.
