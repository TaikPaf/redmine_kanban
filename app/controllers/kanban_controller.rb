# frozen_string_literal: true

class KanbanController < ApplicationController
  menu_item :kanban

  SESSION_KEY = :kanban_query

  before_action :find_optional_project, only: :index
  before_action :find_issue_and_authorize, only: [:card, :allowed_moves, :move]

  rescue_from Query::StatementInvalid, with: :query_statement_invalid
  rescue_from Query::QueryError, with: :query_error

  helper :queries
  include QueriesHelper
  helper :issues
  helper :kanban

  def index
    retrieve_kanban_query
    @setting = KanbanBoardSetting.for_project(@project)
    @board = RedmineKanban::Board.new(@query, @setting, swimlane: @swimlane)
    @board.load if @query.valid?
    if request.xhr?
      render partial: 'kanban/board', locals: {board: @board}
    else
      @saved_queries = IssueQuery.visible.global_or_on_project(@project).sorted.to_a
    end
  end

  def card
    render partial: 'kanban/card', locals: {issue: @issue, board: card_board}
  end

  def allowed_moves
    editable = @issue.attributes_editable?
    render json: {
      status_ids: editable ? @issue.new_statuses_allowed_to(User.current).map(&:id) : [@issue.status_id],
      lane_attributes: editable ? movable_lane_attributes.select {|attr| @issue.safe_attribute?(attr)} : [],
      rankable: User.current.allowed_to?(:rank_kanban_cards, @issue.project)
    }
  end

  def move
    changes = requested_changes
    if changes.any?
      return render_move_error(l(:notice_not_authorized), :forbidden) unless @issue.attributes_editable?

      @issue.init_journal(User.current)
      @issue.lock_version = params[:lock_version] if params[:lock_version].present?
      @issue.safe_attributes = changes
      refused = changes.keys.reject {|attr| @issue.send(attr).to_s == changes[attr].to_s}
      return render_move_error(l(:error_kanban_move_not_allowed)) if refused.any?

      call_hook(:controller_issues_edit_before_save,
                {params: params, issue: @issue, time_entry: nil, journal: @issue.current_journal})
      return render_move_error(@issue.errors.full_messages.join(', ')) unless @issue.save

      call_hook(:controller_issues_edit_after_save,
                {params: params, issue: @issue, time_entry: nil, journal: @issue.current_journal})
    end
    rank_cards if params[:order].present?
    @issue.reload
    render json: {
      id: @issue.id,
      lock_version: @issue.lock_version,
      status_id: @issue.status_id,
      card: render_to_string(partial: 'kanban/card', formats: [:html], locals: {issue: @issue, board: card_board})
    }
  rescue ActiveRecord::StaleObjectError
    render_move_error(l(:notice_issue_update_conflict), :conflict)
  end

  private

  def find_issue_and_authorize
    @issue = Issue.visible.find(params[:id])
    @project = @issue.project
    authorize
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def retrieve_kanban_query
    state = session[SESSION_KEY]
    project_id = @project&.id
    if params[:query_id].present?
      scope = IssueQuery.where(project_id: nil)
      scope = scope.or(IssueQuery.where(project_id: @project.id)) if @project
      @query = scope.find(params[:query_id])
      raise ::Unauthorized unless @query.visible?

      @query.project = @project
      state = {'project_id' => project_id, 'id' => @query.id, 'swimlane' => state&.dig('swimlane')}
    elsif params[:set_filter] || state.nil? || state['project_id'] != project_id
      @query = IssueQuery.new(name: '_', project: @project)
      if params[:set_filter]
        @query.build_from_params(params)
      else
        @query.filters = {'status_id' => {operator: '*', values: ['']}}
      end
      state = {'project_id' => project_id, 'filters' => @query.filters, 'swimlane' => state&.dig('swimlane')}
    else
      @query = IssueQuery.find_by(id: state['id']) if state['id']
      @query ||= IssueQuery.new(name: '_', filters: state['filters'])
      @query.project = @project
    end
    if params[:swimlane].present? && KanbanBoardSetting::SWIMLANES.include?(params[:swimlane])
      state['swimlane'] = params[:swimlane]
    end
    @swimlane = state['swimlane']
    session[SESSION_KEY] = state
  end

  def requested_changes
    changes = {}
    if params[:status_id].present? && params[:status_id].to_i != @issue.status_id
      changes['status_id'] = params[:status_id].to_s
    end
    attr = RedmineKanban::Board::LANE_ATTRIBUTES[params[:lane_field].to_s]
    if attr && movable_lane_attributes.include?(attr) && params.key?(:lane_value) &&
         params[:lane_value].to_s != @issue.send(attr).to_s
      changes[attr] = params[:lane_value].to_s
    end
    changes
  end

  def movable_lane_attributes
    RedmineKanban::Board::MOVABLE_LANES.map {|lane| RedmineKanban::Board::LANE_ATTRIBUTES[lane]}
  end

  def rank_cards
    ids = Array(params[:order]).map(&:to_i).uniq
    allowed = Issue.visible.joins(:project).where(id: ids).
      where(Project.allowed_to_condition(User.current, :rank_kanban_cards)).pluck(:id)
    KanbanIssuePosition.rank(ids & allowed)
  end

  def card_board
    board_project = Project.visible.find_by(id: params[:board_project_id]) if params[:board_project_id].present?
    setting = KanbanBoardSetting.for_project(board_project)
    RedmineKanban::Board.new(IssueQuery.new(name: '_', project: board_project), setting).load_issues([@issue])
  end

  def render_move_error(message, status = :unprocessable_content)
    render json: {error: message}, status: status
  end
end
