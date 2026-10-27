# frozen_string_literal: true

require File.expand_path('../../../test/test_helper', __dir__)

module RedmineKanban
  module TestHelper
    def enable_kanban(project = Project.find(1), role = Role.find(1))
      project.enable_module!(:kanban)
      role.add_permission!(:view_kanban, :rank_kanban_cards, :manage_kanban)
      project
    end
  end
end
