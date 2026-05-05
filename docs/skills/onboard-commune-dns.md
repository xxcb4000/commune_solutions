# Skill — Configurer le DNS d'une commune (Infomaniak + Firebase Hosting)

> Étapes manuelles à exécuter une fois par commune lors de son onboarding.
> Automatisation Infomaniak API + Firebase Hosting custom domain API = phase ultérieure (pas justifiée tant qu'on a < 5 communes en prod).

## Pré-requis

- La commune a un projet Firebase provisionné (cf `tools/provision-commune.py`)
- `tenants/<commune-id>/app.json` est complet avec `build.bundleId` + `build.displayName` + `view.brand`
- Le site public `commune-sites/<commune-id>/` est généré (cf `tools/build-commune-site.py`)
- Accès admin au DNS Infomaniak du domaine `communesolutions.be`
- Accès à la Firebase Console du projet `commune-<commune-id>`

## Étapes

### 1. Créer le site Firebase Hosting

```sh
firebase hosting:sites:create <commune-id> --project commune-<firebase-subfolder>
# Ex : firebase hosting:sites:create awans --project commune-awans
```

Si le projet n'a pas encore Hosting initialisé : Firebase Console → Hosting → Get Started une fois.

### 2. Ajouter le custom domain dans la Firebase Console

Console Firebase → projet `commune-<commune-id>` → Hosting → onglet du site → **Add custom domain**.

Saisir : `<commune-id>.communesolutions.be` (ex : `awans.communesolutions.be`).

Firebase affiche une étape de **vérification** : un enregistrement TXT à ajouter sur `communesolutions.be` (sur le domaine apex), du type :

```
nom : @
type : TXT
valeur : firebase=<projet-id>
TTL : 3600
```

### 3. Ajouter les enregistrements DNS chez Infomaniak

Console Infomaniak → manager.infomaniak.com → Domaines → `communesolutions.be` → **DNS**.

#### 3.a Enregistrement TXT de vérification

Ajouter un enregistrement TXT sur le domaine apex (nom `@` ou laissé vide) :

| Type | Nom | Valeur | TTL |
|---|---|---|---|
| TXT | @ | `firebase=commune-<id>` (copier ce que Firebase a indiqué) | 3600 |

Sauver. Attendre la propagation (parfois quelques minutes, jusqu'à 30 min). Retourner dans la Firebase Console et cliquer **Verify**.

> Si plusieurs communes : **un seul enregistrement TXT par commune**, ils peuvent coexister sur le même domaine apex (TXT supporte plusieurs valeurs).

#### 3.b Enregistrements A pour le sous-domaine

Une fois la vérification OK, Firebase fournit deux IPs `A`. À ce jour Firebase Hosting utilise typiquement `199.36.158.100` mais ça peut changer — toujours **lire les valeurs exactes affichées dans la console Firebase**.

| Type | Nom | Valeur | TTL |
|---|---|---|---|
| A | `<commune-id>` | `<IP-1 fournie par Firebase>` | 3600 |
| A | `<commune-id>` | `<IP-2 fournie par Firebase>` | 3600 |

> Alternativement Firebase peut proposer des records `AAAA` (IPv6) — les ajouter aussi par symétrie.

Sauver. Attendre la propagation.

### 4. Vérifier le SSL

Firebase provisionne automatiquement un certificat Let's Encrypt après la propagation DNS. Compter **15 min à quelques heures**. La console montre l'état : `Pending Setup` → `Pending SSL` → `Connected`.

### 5. Déployer le site

```sh
cd commune-sites/<commune-id>
firebase deploy --project commune-<firebase-subfolder> --only hosting
```

Le site répond sur :
- `<site-name>.web.app` (URL Firebase native) immédiatement
- `<commune-id>.communesolutions.be` une fois le SSL OK

### 6. Tester les Universal Links / App Links

```sh
curl https://<commune-id>.communesolutions.be/.well-known/apple-app-site-association
curl https://<commune-id>.communesolutions.be/.well-known/assetlinks.json
```

Doit retourner du JSON avec :
- iOS : `appID = TJ2759P685.<bundle-id>`
- Android : `package_name = <bundle-id>` (sha256 placeholder à compléter post-build release signé)

### 7. Compléter le sha256 fingerprint Android (après premier build release signé)

```sh
keytool -list -v -keystore <keystore> -alias <alias>
# Récupère SHA256 fingerprint, format `XX:YY:ZZ:...`

# Édite commune-sites/<commune-id>/public/.well-known/assetlinks.json
# Remplace PLACEHOLDER_SHA256_REMPLIR_APRES_PREMIER_BUILD_RELEASE par le vrai SHA256

# Re-deploy
cd commune-sites/<commune-id>
firebase deploy --project commune-<firebase-subfolder> --only hosting
```

## Troubleshooting

- **Verify TXT échoue** : la propagation DNS Infomaniak peut prendre jusqu'à 30 min. `dig TXT communesolutions.be` pour vérifier que le record est visible.
- **SSL bloqué en Pending** : vérifier qu'il n'y a pas de **CAA record** sur le domaine qui bloque Let's Encrypt. Infomaniak peut en avoir mis un par défaut.
- **AASA pas pris en compte par iOS** : vérifier le content-type (doit être `application/json`, pas `text/plain`). Le `firebase.json` template force le bon header. Vérifier aussi que le fichier ne contient pas de BOM.
- **App Links Android pas vérifié** : sha256 incorrect = échec silencieux. Reprendre l'étape 7.

## Quand automatiser

Cette procédure manuelle reste OK jusqu'à ~5 communes en prod. Au-delà, candidate à automatisation :

- **Infomaniak DNS API** : `https://api.infomaniak.com/1/domain/<id>/dns/record` — exige token API + scope DNS write
- **Firebase Hosting Custom Domain API** : `firebasehosting.googleapis.com/v1beta1/projects/<id>/sites/<site>/customDomains` — partie de Firebase Hosting REST

Une fois ces deux automatisés, `tools/provision-commune.py` peut enchaîner provisioning Firebase + DNS + Hosting d'un coup.
