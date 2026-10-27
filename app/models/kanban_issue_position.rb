# frozen_string_literal: true

class KanbanIssuePosition < ApplicationRecord
  belongs_to :issue

  def self.positions_for(issue_ids)
    where(issue_id: issue_ids).pluck(:issue_id, :position).to_h
  end

  # Persists the given order; ids are expected to be already authorized.
  def self.rank(issue_ids)
    issue_ids = issue_ids.map(&:to_i).uniq
    return if issue_ids.empty?

    transaction do
      existing = where(issue_id: issue_ids).index_by(&:issue_id)
      issue_ids.each_with_index do |issue_id, index|
        record = existing[issue_id] || new(issue_id: issue_id)
        record.position = index
        record.save! if record.changed?
      end
    end
  end
end
