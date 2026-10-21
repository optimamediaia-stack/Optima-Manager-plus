# OPTIMA MANAGER — Android

Application Flutter de gestion interne d'Optima Media. Le projet inclut :
- Base SQLite locale pour fonctionnement hors connexion
- Gestion des clients, projets, dépenses et documents commerciaux
- Pro formas, factures, reçus, suivi des paiements partiels
- Génération/impression de documents PDF
- Tableau de bord et réglage de taxe (0 % par défaut)
- Logo officiel fourni par l'utilisateur

## Important
Ce dépôt contient le code source. Aucun APK n'est précompilé dans cet environnement. Le workflow GitHub Actions peut compiler un APK Android à partir du dépôt.

## Compiler avec Flutter installé
```bash
flutter create --platforms=android --org com.optimamedia optima_manager
# Copier pubspec.yaml, lib/, assets/ et .github/ dans le dossier créé
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
APK attendu : `build/app/outputs/flutter-apk/app-release.apk`

## Compiler automatiquement sur GitHub
1. Créez un dépôt GitHub vide et envoyez-y tous les fichiers de ce projet.
2. Ouvrez l'onglet **Actions** et activez les workflows si GitHub le demande.
3. Lancez le workflow **Build Android APK**.
4. Une fois terminé, ouvrez le run et téléchargez l'artefact `optima-manager-apk`.

Le workflow génère le projet Android natif avec `flutter create`, puis compile le code de ce dépôt. Il ne publie rien automatiquement.

## Données et limites de cette version MVP
- Données stockées localement sur un seul appareil ; aucune sauvegarde cloud/synchronisation distante.
- L'APK doit être testé sur appareil réel avant un usage de production.
- Les documents sont des modèles simples : vérifier les exigences légales/comptables locales avant émission officielle.
- Les reçus doivent refléter des paiements réellement reçus. Vérifiez systématiquement les montants et références.
- Une sauvegarde/export de base de données et la sécurité par code/PIN sont des améliorations recommandées avant usage professionnel intensif.
