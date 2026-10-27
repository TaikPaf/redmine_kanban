# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class KanbanControllerTest < Redmine::ControllerTest
  include RedmineKanban::TestHelper

  def setup
    @project = enable_kanban
    @request.session[:user_id] = 2
  end

  def test_index
    get :index, params: {project_id: 'ecookbook'}
    assert_response :success
    assert_select '#kanban-board .kanban-column-header', @project.rolled_up_statuses.count
    assert_select '#kanban-card-1.kanban-card.kanban-draggable'
    assert_select 'form#kanban-form[data-cm-url]'
    assert_select '#main-menu a.kanban'
  end

  def test_index_with_swimlanes_and_filters
    get :index, params: {
      project_id: 'ecookbook', set_filter: '1', swimlane: 'assigned_to',
      f: ['tracker_id'], op: {'tracker_id' => '='}, v: {'tracker_id' => ['1']}
    }
    assert_response :success
    assert_select '.kanban-lane-header', minimum: 1
    assert_select '.kanban-card' do |cards|
      cards.each do |card|
        assert Issue.find(card['data-id']).tracker_id == 1
      end
    end
  end

  def test_index_remembers_filters_in_session
    get :index, params: {project_id: 'ecookbook', set_filter: '1', swimlane: 'tracker',
                         f: ['tracker_id'], op: {'tracker_id' => '='}, v: {'tracker_id' => ['2']}}
    get :index, params: {project_id: 'ecookbook'}
    assert_response :success
    assert_select '#kanban-swimlane option[selected][value=tracker]'
    assert_select '.kanban-card' do |cards|
      cards.each {|card| assert_equal 2, Issue.find(card['data-id']).tracker_id}
    end
  end

  def test_index_with_saved_query
    query = IssueQuery.create!(name: 'Bugs', project: @project, visibility: Query::VISIBILITY_PUBLIC,
                               user_id: 2, filters: {'tracker_id' => {operator: '=', values: ['1']}})
    get :index, params: {project_id: 'ecookbook', query_id: query.id}
    assert_response :success
    assert_select 'h2', text: /Bugs/
  end

  def test_index_xhr_renders_board_only
    get :index, params: {project_id: 'ecookbook'}, xhr: true
    assert_response :success
    assert_select '#kanban-board'
    assert_select '#query_form', 0
  end

  def test_global_index
    get :index
    assert_response :success
    assert_select '#kanban-board'
    assert_select '.kanban-card-project', minimum: 1
  end

  def test_index_without_module_is_forbidden
    @project.disable_module!(:kanban)
    get :index, params: {project_id: 'ecookbook'}
    assert_response :forbidden
  end

  def test_index_without_permission_is_forbidden
    Role.find(1).remove_permission!(:view_kanban)
    get :index, params: {project_id: 'ecookbook'}
    assert_response :forbidden
  end

  def test_allowed_moves
    get :allowed_moves, params: {id: 1}
    assert_response :success
    json = response.parsed_body
    assert_equal Issue.find(1).new_statuses_allowed_to(User.find(2)).map(&:id), json['status_ids']
    assert_includes json['lane_attributes'], 'assigned_to_id'
    assert_equal true, json['rankable']
  end

  def test_move_changes_status_and_creates_journal
    issue = Issue.find(1)
    target = issue.new_statuses_allowed_to(User.find(2)).detect {|s| s.id != issue.status_id}
    assert_difference 'Journal.count' do
      post :move, params: {id: 1, status_id: target.id, lock_version: issue.lock_version,
                           board_project_id: @project.id}, xhr: true
    end
    assert_response :success
    assert_equal target.id, issue.reload.status_id
    json = response.parsed_body
    assert_equal issue.lock_version, json['lock_version']
    assert_match 'kanban-card-1', json['card']
  end

  def test_move_to_status_not_allowed_by_workflow
    issue = Issue.find(1)
    forbidden = IssueStatus.where.not(id: issue.new_statuses_allowed_to(User.find(2)).map(&:id)).first
    assert forbidden
    post :move, params: {id: 1, status_id: forbidden.id}, xhr: true
    assert_response :unprocessable_content
    assert_equal I18n.t(:error_kanban_move_not_allowed), response.parsed_body['error']
    assert_equal issue.status_id, issue.reload.status_id
  end

  def test_move_changes_lane_attribute
    post :move, params: {id: 1, lane_field: 'assigned_to', lane_value: '3'}, xhr: true
    assert_response :success
    assert_equal 3, Issue.find(1).assigned_to_id
  end

  def test_move_to_empty_lane_unassigns
    Issue.find(1).update_column(:assigned_to_id, 3)
    post :move, params: {id: 1, lane_field: 'assigned_to', lane_value: ''}, xhr: true
    assert_response :success
    assert_nil Issue.find(1).assigned_to_id
  end

  def test_move_ignores_non_movable_lane
    post :move, params: {id: 1, lane_field: 'tracker', lane_value: '2'}, xhr: true
    assert_response :success
    assert_equal 1, Issue.find(1).tracker_id
  end

  def test_move_with_stale_lock_version
    issue = Issue.find(1)
    target = issue.new_statuses_allowed_to(User.find(2)).detect {|s| s.id != issue.status_id}
    post :move, params: {id: 1, status_id: target.id, lock_version: issue.lock_version - 1}, xhr: true
    assert_response :conflict
    assert_equal issue.status_id, issue.reload.status_id
  end

  def test_move_with_validation_error
    issue = Issue.find(1)
    target = issue.new_statuses_allowed_to(User.find(2)).detect {|s| s.id != issue.status_id}
    WorkflowPermission.create!(role_id: 1, tracker_id: issue.tracker_id, old_status_id: target.id,
                               field_name: 'due_date', rule: 'required')
    issue.update_column(:due_date, nil)
    # Required fields are checked against the new status' rules.
    post :move, params: {id: 1, status_id: target.id}, xhr: true
    assert_response :unprocessable_content
    assert response.parsed_body['error'].present?
  end

  def test_move_without_edit_permission
    Role.find(1).remove_permission!(:edit_issues)
    issue = Issue.find(1)
    post :move, params: {id: 1, status_id: 2}, xhr: true
    assert_response :forbidden
    assert_equal issue.status_id, issue.reload.status_id
  end

  def test_move_ranks_cards
    post :move, params: {id: 1, order: ['3', '1', '2']}, xhr: true
    assert_response :success
    assert_equal({3 => 0, 1 => 1, 2 => 2}, KanbanIssuePosition.positions_for([1, 2, 3]))
  end

  def test_move_does_not_rank_without_permission
    Role.find(1).remove_permission!(:rank_kanban_cards)
    post :move, params: {id: 1, order: ['3', '1', '2']}, xhr: true
    assert_response :success
    assert_equal({}, KanbanIssuePosition.positions_for([1, 2, 3]))
  end

  def test_move_invisible_issue
    @request.session[:user_id] = nil
    post :move, params: {id: 4, status_id: 2}, xhr: true
    assert_response :not_found
  end

  def test_card
    get :card, params: {id: 1, board_project_id: @project.id}
    assert_response :success
    assert_select '#kanban-card-1'
  end
end
