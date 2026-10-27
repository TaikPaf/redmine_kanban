# frozen_string_literal: true

get 'kanban', to: 'kanban#index', as: 'kanban'
get 'projects/:project_id/kanban', to: 'kanban#index', as: 'project_kanban'
get 'kanban/issues/:id/card', to: 'kanban#card', as: 'kanban_card'
get 'kanban/issues/:id/allowed_moves', to: 'kanban#allowed_moves', as: 'kanban_allowed_moves'
post 'kanban/issues/:id/move', to: 'kanban#move', as: 'kanban_move'
patch 'projects/:project_id/kanban/settings', to: 'kanban_settings#update', as: 'project_kanban_settings'
