# frozen_string_literal: true

# Demo data for local development: bundle exec rails runner plugins/redmine_kanban/dev/seed.rb
# Admin login stays Redmine's default (admin / admin).

Redmine::DefaultData::Loader.load('fr') unless IssueStatus.any?

admin = User.find_by(login: 'admin')
admin.update!(must_change_passwd: false, language: 'fr')

manager = Role.find_by(name: 'Manager') || Role.where(builtin: 0).first
manager.add_permission!(:view_kanban, :rank_kanban_cards, :manage_kanban)

dev = User.find_by(login: 'alice') || User.create!(
  login: 'alice', firstname: 'Alice', lastname: 'Martin', mail: 'alice@example.test',
  password: 'alice-dev-1234', language: 'fr'
)

project = Project.find_by(identifier: 'demo') || Project.create!(
  name: 'Projet démo', identifier: 'demo', is_public: true,
  tracker_ids: Tracker.pluck(:id),
  enabled_module_names: %w(issue_tracking time_tracking kanban)
)
project.enable_module!(:kanban)
[admin, dev].each do |user|
  next if Member.exists?(project: project, user: user)

  Member.create!(project: project, principal: user, roles: [manager])
end

if project.issues.empty?
  version = Version.create!(project: project, name: 'v1.0', effective_date: Date.today + 30)
  Version.create!(project: project, name: 'v1.1')
  category = IssueCategory.create!(project: project, name: 'Front')
  IssueCategory.create!(project: project, name: 'Back')
  statuses = IssueStatus.sorted.to_a
  priorities = IssuePriority.active.to_a
  subjects = [
    'Page de connexion', "Export CSV des factures", 'Notifications par e-mail', 'Recherche plein texte',
    'Corriger le tri des dates', 'Optimiser la requête du tableau de bord', 'Ajouter le mode sombre',
    'Traduire les libellés', 'Migrer vers PostgreSQL 16', 'Écrire la documentation API',
    'Gestion des rôles', "Import d'utilisateurs", 'Corriger le bug de pagination', 'Tests de charge',
    'Refonte du menu', 'Webhook de paiement', 'Cache des avatars', 'Journal des connexions'
  ]
  User.current = admin
  subjects.each_with_index do |subject, i|
    Issue.create!(
      project: project, tracker: Tracker.sorted.to_a[i % Tracker.count], author: admin,
      subject: subject, status: statuses[i % [statuses.size, 5].min],
      priority: priorities[i % priorities.size],
      assigned_to: [admin, dev, nil][i % 3],
      fixed_version: i.even? ? version : nil, category: i % 3 == 0 ? category : nil,
      due_date: Date.today + (i - 4), estimated_hours: (i % 4) + 1, done_ratio: (i * 10) % 100
    )
  end
end

puts "Demo project ready: /projects/#{project.identifier}/kanban"
