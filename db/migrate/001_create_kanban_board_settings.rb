# frozen_string_literal: true

class CreateKanbanBoardSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :kanban_board_settings do |t|
      t.references :project, null: false, index: {unique: true},
                   foreign_key: {on_delete: :cascade}, type: :integer
      t.text :settings
      t.timestamps
    end
  end
end
