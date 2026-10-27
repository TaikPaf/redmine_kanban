# frozen_string_literal: true

Redmine::Plugin.register :redmine_kanban do
  name 'Redmine Kanban'
  author 'TaikPaf'
  description 'Kanban board for Redmine issues: workflow-aware drag and drop, swimlanes, WIP limits and saved queries.'
  version '1.0.0'
  url 'https://github.com/TaikPaf/redmine_kanban'
  requires_redmine version_or_higher: '7.0.0'

  settings default: {
    'swimlane' => 'none',
    'card_fields' => %w(tracker priority assigned_to due_date fixed_version done_ratio relations subtasks),
    'closed_days' => '14',
    'max_cards' => '500'
  }, partial: 'settings/kanban_settings'

  project_module :kanban do
    permission :view_kanban, {kanban: [:index, :card, :allowed_moves, :move]}, read: true
    permission :rank_kanban_cards, {}, require: :loggedin
    permission :manage_kanban, {kanban_settings: [:update]}, require: :member
  end

  menu :project_menu, :kanban, {controller: 'kanban', action: 'index'},
       caption: :label_kanban, after: :issues, param: :project_id
  menu :application_menu, :kanban, {controller: 'kanban', action: 'index'},
       caption: :label_kanban, after: :issues,
       if: proc { User.current.allowed_to?(:view_kanban, nil, global: true) }
end

ProjectsHelper.prepend(RedmineKanban::ProjectsHelperPatch) unless ProjectsHelper <= RedmineKanban::ProjectsHelperPatch
