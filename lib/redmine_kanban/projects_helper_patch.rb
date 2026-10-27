# frozen_string_literal: true

module RedmineKanban
  module ProjectsHelperPatch
    def project_settings_tabs
      tabs = super
      if @project.module_enabled?(:kanban) && User.current.allowed_to?(:manage_kanban, @project)
        tabs << {name: 'kanban', action: :manage_kanban, partial: 'projects/settings/kanban', label: :label_kanban}
      end
      tabs
    end
  end
end
