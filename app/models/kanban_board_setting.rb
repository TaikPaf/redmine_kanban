# frozen_string_literal: true

class KanbanBoardSetting < ApplicationRecord
  SWIMLANES = %w(none assigned_to tracker priority fixed_version category project parent).freeze
  CARD_FIELDS = %w(tracker priority assigned_to author due_date start_date fixed_version category
                   done_ratio estimated_hours spent_hours relations subtasks).freeze

  belongs_to :project
  serialize :settings, coder: JSON

  validates :project_id, uniqueness: true

  def self.for_project(project)
    return new if project.nil?

    find_or_initialize_by(project_id: project.id)
  end

  def self.plugin_defaults
    Setting.plugin_redmine_kanban.presence || {}
  end

  def settings
    super || {}
  end

  def configured_columns
    Array(settings['columns']).filter_map do |c|
      next unless c.is_a?(Hash) && c['status_id'].to_i > 0

      {'status_id' => c['status_id'].to_i, 'wip_limit' => c['wip_limit'].to_i.positive? ? c['wip_limit'].to_i : nil}
    end
  end

  def statuses
    ids = configured_columns.pluck('status_id')
    if ids.any?
      by_id = IssueStatus.where(id: ids).index_by(&:id)
      ids.filter_map {|id| by_id[id]}
    else
      default_statuses
    end
  end

  def default_statuses
    statuses = project ? project.rolled_up_statuses.to_a : []
    statuses.presence || IssueStatus.sorted.to_a
  end

  def wip_limit(status_id)
    configured_columns.detect {|c| c['status_id'] == status_id}&.dig('wip_limit')
  end

  def swimlane
    value = settings['swimlane'].presence || self.class.plugin_defaults['swimlane']
    SWIMLANES.include?(value) ? value : 'none'
  end

  def card_fields
    value = settings['card_fields'] || self.class.plugin_defaults['card_fields'] || []
    Array(value) & CARD_FIELDS
  end

  def closed_days
    integer_setting('closed_days', 14)
  end

  def max_cards
    [integer_setting('max_cards', 500), 1].max
  end

  # Expects params shaped like the project settings form.
  def assign_form(params)
    raw_columns = params[:columns] || {}
    raw_columns = raw_columns.to_unsafe_h if raw_columns.respond_to?(:to_unsafe_h)
    columns = raw_columns.filter_map do |status_id, c|
      next unless c['enabled'] == '1'

      {'status_id' => status_id.to_i, 'wip_limit' => c['wip_limit'].to_i, 'position' => c['position'].to_i}
    end
    columns.sort_by! {|c| c['position']}
    columns.each {|c| c.delete('position')}

    self.settings = {
      'columns' => columns,
      'swimlane' => SWIMLANES.include?(params[:swimlane]) ? params[:swimlane] : 'none',
      'card_fields' => Array(params[:card_fields]) & CARD_FIELDS,
      'closed_days' => params[:closed_days].to_s,
      'max_cards' => params[:max_cards].to_s
    }
  end

  private

  def integer_setting(name, fallback)
    value = settings[name].presence || self.class.plugin_defaults[name].presence
    value.nil? ? fallback : value.to_i
  end
end
