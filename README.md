# Redmine Kanban

Plugin Redmine qui ajoute un tableau Kanban pour les demandes, par projet et multi-projets.

Compatible avec **Redmine 7.0+** (Rails 8.1, Ruby 3.2 à 4.0).

## Fonctionnalités

- **Colonnes = statuts**, configurables par projet : choix des statuts, ordre (glisser-déposer) et **limites WIP** (la colonne passe en rouge si la limite est dépassée).
- **Glisser-déposer qui respecte le workflow** : pendant le déplacement, les colonnes autorisées pour la carte sont mises en évidence. Le changement passe par le modèle `Issue` de Redmine : workflow, champs obligatoires, champs en lecture seule, permissions, journal (historique) et notifications sont respectés.
- **Couloirs** (*swimlanes*) : par assigné, tracker, priorité, version, catégorie, projet ou tâche parente. Déplacer une carte d'un couloir à l'autre modifie l'assigné, la priorité, la version ou la catégorie.
- **Ordre manuel des cartes** dans une colonne (permission dédiée).
- **Filtres Redmine complets** et **requêtes enregistrées** des demandes. Les filtres et le couloir choisi sont mémorisés en session.
- **Cartes configurables** : tracker, priorité, assigné, auteur, dates de début et d'échéance (retard en rouge), version, catégorie, avancement, temps estimé et passé, sous-tâches (fermées/total) et indicateur « bloquée ».
- **Menu contextuel natif** (clic droit, Ctrl/Maj+clic pour une sélection multiple) : modification en masse, assignation, suppression, etc.
- **Gestion des conflits** : si la demande a été modifiée entre-temps, la carte revient à sa place avec un message.
- Recherche instantanée, colonnes et couloirs repliables (mémorisés dans le navigateur), masquage des couloirs vides, rafraîchissement sans recharger la page, mode plein écran.
- Les demandes fermées ne sont affichées que pendant N jours (14 par défaut), avec un nombre maximum de cartes pour garder un tableau rapide.
- Tableau **multi-projets** (`/kanban`) sur tous les projets où l'utilisateur peut voir le Kanban.
- Interface en français et en anglais.

## Installation

```bash
cd /chemin/vers/redmine/plugins
git clone https://github.com/TaikPaf/redmine_kanban.git
cd ..
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
```

Redémarrez ensuite Redmine (Puma, Passenger…).

## Configuration

1. **Administration → Rôles et permissions** : donnez aux rôles concernés les permissions :
   - *Voir le tableau Kanban*
   - *Réordonner les cartes Kanban*
   - *Configurer le tableau Kanban*

   Déplacer une carte vers un autre statut ou un autre couloir nécessite aussi le droit de modifier la demande (*Modifier les demandes*) et une transition autorisée dans le workflow.
2. **Projet → Configuration → Modules** : activez le module **Kanban**.
3. **Projet → Configuration → Kanban** : colonnes, limites WIP, couloirs par défaut et champs des cartes.
4. **Administration → Plugins → Redmine Kanban → Configurer** : valeurs par défaut pour le tableau multi-projets et les projets non configurés.

## Désinstallation

```bash
bundle exec rake redmine:plugins:migrate NAME=redmine_kanban VERSION=0 RAILS_ENV=production
rm -rf plugins/redmine_kanban
```

## Tests

Depuis la racine de Redmine :

```bash
bundle exec rake redmine:plugins:test NAME=redmine_kanban RAILS_ENV=test
```

Les tests tournent aussi automatiquement sur GitHub Actions (Redmine 7.0.2, SQLite et PostgreSQL).

## Environnement de développement (Docker)

Le dossier `dev/` lance un Redmine 7.0.2 local qui contient le plugin :

```bash
cd dev
docker compose up -d redmine
docker compose exec redmine bundle exec rails runner plugins/redmine_kanban/dev/seed.rb
```

Ouvrez ensuite http://localhost:3000/projects/demo/kanban (compte `admin` / `admin`, celui par défaut de Redmine, à n'utiliser qu'en local).
Sous Windows, Redmine ne voit pas les modifications de fichiers : lancez `docker compose restart redmine` après chaque changement.

Pour lancer les tests dans Docker :

```bash
cd dev
docker compose --profile test run --rm test
```

## Licence

GPL v2 ou ultérieure, comme Redmine. Voir le fichier `LICENSE`.
