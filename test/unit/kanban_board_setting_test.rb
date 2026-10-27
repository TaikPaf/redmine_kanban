# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class KanbanBoardSettingTest < ActiveSupport::TestCase
  include RedmineKanban::TestHelper

  def test_defaults_use_project_workflow_statuses
    setting = KanbanBoardSetting.for_project(Project.find(1))
    assert setting.new_record?
    assert_equal Project.find(1).rolled_up_statuses.map(&:id), setting.statuses.map(&:id)
    assert_equal 'none', setting.swimlane
    assert_equal 14, setting.closed_days
    assert_equal 500, setting.max_cards
  end

  def test_global_board_uses_all_statuses
    setting = KanbanBoardSetting.for_project(nil)
    assert_equal IssueStatus.sorted.map(&:id), setting.statuses.map(&:id)
  end

  def test_assign_form_keeps_enabled_columns_in_position_order
    setting = KanbanBoardSetting.for_project(Project.find(1))
    setting.assign_form(
      columns: {
        '1' => {'enabled' => '1', 'position' => '2', 'wip_limit' => '0'},
        '2' => {'enabled' => '1', 'position' => '0', 'wip_limit' => '3'},
        '3' => {'enabled' => '0', 'position' => '1', 'wip_limit' => '5'}
      },
      swimlane: 'assigned_to',
      card_fields: ['', 'tracker', 'bogus'],
      closed_days: '0',
      max_cards: '50'
    )
    assert setting.save
    setting.reload

    assert_equal [2, 1], setting.statuses.map(&:id)
    assert_equal 3, setting.wip_limit(2)
    assert_nil setting.wip_limit(1)
    assert_equal 'assigned_to', setting.swimlane
    assert_equal ['tracker'], setting.card_fields
    assert_equal 0, setting.closed_days
    assert_equal 50, setting.max_cards
  end

  def test_invalid_swimlane_falls_back_to_none
    setting = KanbanBoardSetting.new(settings: {'swimlane' => 'bogus'})
    assert_equal 'none', setting.swimlane
  end

  def test_plugin_settings_provide_defaults
    with_settings plugin_redmine_kanban: {'swimlane' => 'priority', 'max_cards' => '42', 'card_fields' => ['priority']} do
      setting = KanbanBoardSetting.for_project(Project.find(1))
      assert_equal 'priority', setting.swimlane
      assert_equal 42, setting.max_cards
      assert_equal ['priority'], setting.card_fields
    end
  end

  def test_settings_are_deleted_with_project
    project = Project.find(1)
    KanbanBoardSetting.for_project(project).tap {|s| s.assign_form(swimlane: 'tracker')}.save!
    assert_difference 'KanbanBoardSetting.count', -1 do
      project.destroy
    end
  end
end
