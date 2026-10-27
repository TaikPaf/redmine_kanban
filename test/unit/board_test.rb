# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineKanban::BoardTest < ActiveSupport::TestCase
  include RedmineKanban::TestHelper

  def setup
    @project = enable_kanban
    User.current = User.find(2)
  end

  def teardown
    User.current = nil
  end

  def build_board(swimlane: nil, setting: KanbanBoardSetting.for_project(@project))
    query = IssueQuery.new(name: '_', project: @project)
    query.filters = {'status_id' => {operator: '*', values: ['']}}
    RedmineKanban::Board.new(query, setting, swimlane: swimlane).load
  end

  def test_issues_are_dispatched_in_status_columns
    board = build_board
    lane = board.lanes.first
    board.statuses.each do |status|
      assert board.cell(lane, status).all? {|issue| issue.status_id == status.id}
    end
    assert_equal board.issues.size, board.columns.sum(&:count)
  end

  def test_issues_of_projects_without_kanban_module_are_excluded
    board = build_board
    assert board.issues.any?
    assert board.issues.all? {|issue| issue.project.module_enabled?(:kanban)}
  end

  def test_assignee_swimlanes
    board = build_board(swimlane: 'assigned_to')
    assert board.lane_movable?
    assert_equal 'assigned_to_id', board.lane_attribute
    assert_includes board.lanes.map(&:id), ''
    board.issues.each do |issue|
      lane = board.lanes.detect {|l| l.id == issue.assigned_to_id.to_s}
      assert lane, "missing lane for issue #{issue.id}"
      assert_includes board.cell(lane, issue.status), issue
    end
  end

  def test_tracker_swimlanes_are_not_movable
    board = build_board(swimlane: 'tracker')
    assert_not board.lane_movable?
    assert_equal board.issues.map(&:tracker_id).uniq.sort.map(&:to_s), board.lanes.map(&:id).sort
  end

  def test_closed_issues_older_than_closed_days_are_hidden
    closed = Issue.find(8)
    assert closed.closed?
    closed.update_column(:closed_on, 1.year.ago)

    assert_not_includes build_board.issues, closed

    setting = KanbanBoardSetting.for_project(@project)
    setting.settings = {'closed_days' => '0', 'columns' => [{'status_id' => closed.status_id}]}
    assert_includes build_board(setting: setting).issues, closed
  end

  def test_max_cards_truncates_board
    setting = KanbanBoardSetting.for_project(@project)
    setting.settings = {'max_cards' => '2'}
    board = build_board(setting: setting)
    assert board.truncated?
    assert_equal 2, board.issues.size
  end

  def test_manual_positions_take_precedence
    board = build_board
    status_id, issues = board.issues.group_by(&:status_id).detect {|_, list| list.size > 1}
    assert status_id
    reversed = issues.map(&:id).reverse
    KanbanIssuePosition.rank(reversed)

    board = build_board
    assert_equal reversed, board.issues.select {|i| i.status_id == status_id}.map(&:id)
  end

  def test_blocked_and_subtasks_indicators
    IssueRelation.delete_all
    blocker = Issue.find(1)
    blocked = Issue.find(2)
    IssueRelation.create!(issue_from: blocker, issue_to: blocked, relation_type: 'blocks')
    child = Issue.generate!(project: @project, parent_issue_id: blocker.id)

    board = build_board
    assert board.blocked?(board.issues.detect {|i| i.id == blocked.id})
    assert_not board.blocked?(board.issues.detect {|i| i.id == blocker.id})
    assert_equal({total: 1, closed: 0}, board.subtasks(board.issues.detect {|i| i.id == blocker.id}))
    assert child
  end
end
