# frozen_string_literal: true

module RedmineKanban
  class Board
    Lane = Struct.new(:id, :name, :object, keyword_init: true)
    Column = Struct.new(:status, :wip_limit, :count, :estimated_hours, keyword_init: true) do
      def over_limit?
        wip_limit.present? && count > wip_limit
      end
    end

    LANE_ATTRIBUTES = {
      'assigned_to' => 'assigned_to_id',
      'tracker' => 'tracker_id',
      'priority' => 'priority_id',
      'fixed_version' => 'fixed_version_id',
      'category' => 'category_id',
      'project' => 'project_id',
      'parent' => 'parent_id'
    }.freeze
    # Lanes whose value can be changed by dropping a card into another lane.
    MOVABLE_LANES = %w(assigned_to priority fixed_version category).freeze

    attr_reader :query, :setting, :swimlane, :project, :user, :issues

    def initialize(query, setting, swimlane: nil, user: User.current)
      @query = query
      @setting = setting
      @project = query.project
      @user = user
      @swimlane = KanbanBoardSetting::SWIMLANES.include?(swimlane) ? swimlane : setting.swimlane
    end

    def statuses
      @statuses ||= setting.statuses
    end

    def card_fields
      setting.card_fields
    end

    def load
      limit = setting.max_cards
      loaded = query.issues(
        conditions: self.class.sanitize_conditions(board_conditions),
        include: [:assigned_to, :tracker, :author, :fixed_version, :category],
        limit: limit + 1
      )
      @truncated = loaded.size > limit
      @issues = sort_issues(loaded.first(limit))
      preload_card_data
      self
    end

    # Used to render isolated cards after a move.
    def load_issues(list)
      @truncated = false
      @issues = list
      preload_card_data
      self
    end

    def truncated?
      @truncated
    end

    def columns
      @columns ||= statuses.map do |status|
        in_column = issues.select {|i| i.status_id == status.id}
        Column.new(
          status: status,
          wip_limit: setting.wip_limit(status.id),
          count: in_column.size,
          estimated_hours: in_column.sum {|i| i.estimated_hours.to_f}
        )
      end
    end

    def lanes
      @lanes ||=
        if swimlane == 'none'
          [Lane.new(id: '', name: nil, object: nil)]
        else
          build_lanes
        end
    end

    def lane_movable?
      MOVABLE_LANES.include?(swimlane)
    end

    def lane_attribute
      LANE_ATTRIBUTES[swimlane]
    end

    def cell(lane, status)
      cells[[lane.id, status.id]] || []
    end

    def lane_count(lane)
      statuses.sum {|status| cell(lane, status).size}
    end

    def blocked?(issue)
      @blocked_ids&.include?(issue.id)
    end

    def subtasks(issue)
      @subtasks && @subtasks[issue.id]
    end

    def editable?(issue)
      @editable ||= {}
      @editable.fetch(issue.id) {@editable[issue.id] = issue.attributes_editable?(user)}
    end

    def rankable?(issue)
      @rankable ||= {}
      @rankable.fetch(issue.project_id) do
        @rankable[issue.project_id] = user.allowed_to?(:rank_kanban_cards, issue.project)
      end
    end

    def draggable?(issue)
      editable?(issue) || rankable?(issue)
    end

    def lane_id_for(issue)
      return '' if swimlane == 'none'

      issue.send(lane_attribute).to_s
    end

    def self.sanitize_conditions(conditions)
      Issue.send(:sanitize_sql_array, conditions)
    end

    private

    def board_conditions
      sql = +"#{Issue.table_name}.status_id IN (:status_ids)"
      values = {status_ids: statuses.map(&:id).presence || [0]}
      sql << " AND #{Project.allowed_to_condition(user, :view_kanban)}"
      if setting.closed_days > 0
        sql << " AND (#{IssueStatus.table_name}.is_closed = :open OR #{Issue.table_name}.closed_on >= :closed_since)"
        values[:open] = false
        values[:closed_since] = setting.closed_days.days.ago
      end
      [sql, values]
    end

    def sort_issues(list)
      positions = KanbanIssuePosition.positions_for(list.map(&:id))
      list.each_with_index.sort_by do |issue, index|
        position = positions[issue.id]
        [position.nil? ? 1 : 0, position || 0, -(issue.priority&.position || 0), index]
      end.map(&:first)
    end

    def preload_card_data
      ids = issues.map(&:id)
      return if ids.empty?

      Issue.load_visible_spent_hours(issues, user) if card_fields.include?('spent_hours')
      if card_fields.include?('relations')
        @blocked_ids = IssueRelation.
          joins(issue_from: :status).
          where(relation_type: IssueRelation::TYPE_BLOCKS, issue_to_id: ids).
          where(IssueStatus.table_name => {is_closed: false}).
          distinct.pluck(:issue_to_id).to_set
      end
      if card_fields.include?('subtasks')
        @subtasks = Hash.new {|h, k| h[k] = {total: 0, closed: 0}}
        Issue.visible(user).joins(:status).where(parent_id: ids).
          group(:parent_id, "#{IssueStatus.table_name}.is_closed").count.each do |(parent_id, closed), count|
          @subtasks[parent_id][:total] += count
          @subtasks[parent_id][:closed] += count if ActiveModel::Type::Boolean.new.cast(closed)
        end
      end
    end

    def cells
      @cells ||= issues.group_by {|issue| [lane_id_for(issue), issue.status_id]}
    end

    def build_lanes
      objects = lane_candidates.to_a
      objects.concat(issues.filter_map {|issue| lane_object(issue)})
      objects = objects.uniq(&:id)
      lanes = sort_lane_objects(objects).map {|o| Lane.new(id: o.id.to_s, name: o.to_s, object: o)}
      # Values the user cannot see (e.g. a private parent) still need a lane.
      known = lanes.map(&:id)
      issues.map {|issue| lane_id_for(issue)}.uniq.each do |id|
        lanes << Lane.new(id: id, name: "##{id}", object: nil) if id.present? && known.exclude?(id)
      end
      if issues.any? {|issue| issue.send(lane_attribute).nil?} || (lane_movable? && swimlane != 'priority')
        lanes << Lane.new(id: '', name: nil, object: nil)
      end
      lanes
    end

    def lane_object(issue)
      case swimlane
      when 'parent' then parents[issue.parent_id]
      else issue.send(swimlane)
      end
    end

    def parents
      @parents ||= Issue.visible(user).where(id: issues.filter_map(&:parent_id).uniq).index_by(&:id)
    end

    def lane_candidates
      case swimlane
      when 'priority' then IssuePriority.active
      when 'fixed_version' then project ? project.shared_versions.open : []
      when 'category' then project ? project.issue_categories : []
      when 'assigned_to' then project ? project.assignable_users : []
      else []
      end
    end

    def sort_lane_objects(objects)
      case swimlane
      when 'priority' then objects.sort_by {|o| -o.position.to_i}
      when 'tracker' then objects.sort_by {|o| o.position.to_i}
      when 'project' then objects.sort_by {|o| o.lft.to_i}
      when 'parent' then objects.sort_by(&:id)
      when 'fixed_version' then objects.sort
      else objects.sort_by {|o| o.to_s.downcase}
      end
    end
  end
end
