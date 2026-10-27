# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class KanbanSettingsControllerTest < Redmine::ControllerTest
  include RedmineKanban::TestHelper

  def setup
    @project = enable_kanban
    @request.session[:user_id] = 2
  end

  def test_update
    patch :update, params: {
      project_id: 'ecookbook',
      columns: {'1' => {'enabled' => '1', 'position' => '1', 'wip_limit' => '4'},
                '2' => {'enabled' => '1', 'position' => '0', 'wip_limit' => ''}},
      swimlane: 'priority', card_fields: ['tracker', 'assigned_to'], closed_days: '7', max_cards: '100'
    }
    assert_redirected_to '/projects/ecookbook/settings/kanban'
    setting = KanbanBoardSetting.find_by(project_id: 1)
    assert_equal [2, 1], setting.statuses.map(&:id)
    assert_equal 4, setting.wip_limit(1)
    assert_equal 'priority', setting.swimlane
    assert_equal %w(tracker assigned_to), setting.card_fields
  end

  def test_update_without_permission
    Role.find(1).remove_permission!(:manage_kanban)
    patch :update, params: {project_id: 'ecookbook', swimlane: 'priority'}
    assert_response :forbidden
  end
end

class KanbanProjectSettingsTabTest < Redmine::ControllerTest
  include RedmineKanban::TestHelper
  tests ProjectsController

  def test_settings_tab
    enable_kanban
    @request.session[:user_id] = 2
    get :settings, params: {id: 'ecookbook', tab: 'kanban'}
    assert_response :success
    assert_select 'form#kanban-settings-form .kanban-settings-columns tr[data-status-id]', IssueStatus.count
  end

  def test_settings_tab_hidden_when_module_disabled
    @request.session[:user_id] = 2
    get :settings, params: {id: 'ecookbook'}
    assert_response :success
    assert_select 'a#tab-kanban', 0
  end
end
