# frozen_string_literal: true

module KanbanHelper
  SWIMLANE_LABELS = {
    'none' => :label_kanban_no_swimlane,
    'assigned_to' => :field_assigned_to,
    'tracker' => :field_tracker,
    'priority' => :field_priority,
    'fixed_version' => :field_fixed_version,
    'category' => :field_category,
    'project' => :field_project,
    'parent' => :field_parent_issue
  }.freeze

  CARD_FIELD_LABELS = {
    'tracker' => :field_tracker,
    'priority' => :field_priority,
    'assigned_to' => :field_assigned_to,
    'author' => :field_author,
    'due_date' => :field_due_date,
    'start_date' => :field_start_date,
    'fixed_version' => :field_fixed_version,
    'category' => :field_category,
    'done_ratio' => :field_done_ratio,
    'estimated_hours' => :field_estimated_hours,
    'spent_hours' => :label_spent_time,
    'relations' => :label_kanban_blocked_indicator,
    'subtasks' => :label_subtask_plural
  }.freeze

  EMPTY_LANE_LABELS = {
    'assigned_to' => :label_kanban_unassigned,
    'fixed_version' => :label_kanban_no_version,
    'category' => :label_kanban_no_category,
    'parent' => :label_kanban_no_parent
  }.freeze

  def kanban_swimlane_options(selected)
    options_for_select(KanbanBoardSetting::SWIMLANES.map {|s| [l(SWIMLANE_LABELS[s]), s]}, selected)
  end

  def kanban_card_field_label(field)
    l(CARD_FIELD_LABELS[field])
  end

  def kanban_lane_name(board, lane)
    return lane.name if lane.name.present?

    l(EMPTY_LANE_LABELS[board.swimlane] || :label_none)
  end

  def kanban_lane_avatar(board, lane)
    return unless board.swimlane == 'assigned_to' && lane.object

    avatar(lane.object, size: 20)
  end

  def kanban_board_path(project, options = {})
    project ? project_kanban_path(project, options) : kanban_path(options)
  end

  def kanban_due_class(issue)
    return unless issue.due_date && !issue.closed?

    if issue.due_date < User.current.today
      'kanban-overdue'
    elsif issue.due_date <= User.current.today + 2
      'kanban-due-soon'
    end
  end

  def kanban_hours(value)
    format_hours(value.to_f)
  end

  def kanban_column_style(board)
    "--kanban-columns: #{board.statuses.size};"
  end
end
