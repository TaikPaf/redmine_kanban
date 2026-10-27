# frozen_string_literal: true

class KanbanSettingsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def update
    setting = KanbanBoardSetting.for_project(@project)
    setting.assign_form(params)
    if setting.save
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = setting.errors.full_messages.join(', ')
    end
    redirect_to settings_project_path(@project, tab: 'kanban')
  end
end
