# Fastlane — distribution stores

Lanes pour builder et uploader les apps de commune sur TestFlight (et plus tard Google Play).

## Prérequis

### Outils locaux

```sh
# Ruby (>= 3.0) déjà installé via macOS / brew
gem install bundler
bundle install   # depuis la racine du repo
```

### App Store Connect API key

Utilise la clé `.p8` de Mosa Data Engineering (Team ID `TJ2759P685`). La clé se trouve sur la machine de Vincent à :

```
/Users/vincentbonhomme/Documents/Dev/commune_awans/commune_awans_ios/AuthKey_JD5MN9XL6W.p8
```

Pour les builds locaux : crée `.env.fastlane` à la racine du repo (gitignored) avec :

```sh
APP_STORE_CONNECT_API_KEY_ID=JD5MN9XL6W
APP_STORE_CONNECT_API_KEY_ISSUER_ID=6d48c126-e579-417b-9753-8f458d519b55
APP_STORE_CONNECT_API_KEY_PATH=/Users/vincentbonhomme/Documents/Dev/commune_awans/commune_awans_ios/AuthKey_JD5MN9XL6W.p8
```

Pour la CI (GitHub Actions) : encode la clé en base64 + ajoute-la aux secrets de l'environment commune :

```sh
base64 -i AuthKey_JD5MN9XL6W.p8 | pbcopy
# Settings → Environments → <commune_id> → Add secret
#   APP_STORE_CONNECT_API_KEY_CONTENT_B64 (paste)
#   APP_STORE_CONNECT_API_KEY_ID JD5MN9XL6W
#   APP_STORE_CONNECT_API_KEY_ISSUER_ID 6d48c126-e579-417b-9753-8f458d519b55
```

### Apple App Store Connect — record par commune

Avant le premier upload TestFlight pour une commune, il faut **créer le record d'app dans App Store Connect** avec son bundle ID :

```
https://appstoreconnect.apple.com → My Apps → +
  Bundle ID : be.communesolutions.<commune-id>  (doit déjà exister sur developer.apple.com)
  Name : <Nom commune>
  SKU : commune-<id>-ios
```

L'auto-provisioning de xcodebuild (`-allowProvisioningUpdates` + API key) crée automatiquement les bundle IDs sur `developer.apple.com` et les profils dev/distribution. Mais le record App Store Connect lui-même doit être créé manuellement (Apple ne l'auto-crée pas via l'API).

## Lanes

### `bundle exec fastlane archive commune_id:<id>`

Build une archive `.ipa` signée App Store, sans upload. Utile pour :
- Tester que la signature fonctionne
- Distribuer manuellement à TestFlight via Transporter / Xcode Organizer
- Archiver localement pour debug

Output : `spike/ios/build/fastlane/CommuneSpike-<commune-id>.ipa`

### `bundle exec fastlane testflight commune_id:<id>`

Build + upload TestFlight. Utilisé en CI pour publier des builds beta.

```sh
bundle exec fastlane ios testflight commune_id:spike
```

Le changelog est auto-généré avec le timestamp UTC. Pour un changelog custom, modifier le Fastfile ou ajouter une option lane.

## Workflow CI

Voir `.github/workflows/release-commune-app.yml` (à créer en phase 12.4 quand on aura validé le lane local en premier).

## Dépannage

**`Could not find ...` au runtime** : la clé `.p8` ou ses metadonnées (key_id, issuer_id) sont fausses. Vérifier `.env.fastlane`.

**`No matching profiles found`** : `xcodebuild -allowProvisioningUpdates` n'a pas pu auto-créer le profile distribution. Vérifier que le bundle ID existe sur `developer.apple.com` (créé automatiquement par xcodebuild si l'API key a le rôle Admin).

**`The bundle ID has already been used`** : le bundle ID est occupé par une autre app sur ASC. Utiliser un suffixe : `be.communesolutions.<commune>2`.
