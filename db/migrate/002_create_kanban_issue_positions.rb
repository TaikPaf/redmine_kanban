# frozen_string_literal: true

class CreateKanbanIssuePositions < ActiveRecord::Migration[7.2]
  def change
    create_table :kanban_issue_positions do |t|
      t.references :issue, null: false, index: {unique: true},
                   foreign_key: {on_delete: :cascade}, type: :integer
      t.integer :position, null: false, default: 0
    end
  end
end
