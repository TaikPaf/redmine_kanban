(function ($) {
  'use strict';

  var LANE_ATTRIBUTES = {
    assigned_to: 'assigned_to_id',
    priority: 'priority_id',
    fixed_version: 'fixed_version_id',
    category: 'category_id'
  };

  function readStore(key, fallback) {
    try {
      var value = window.localStorage.getItem(key);
      return value === null ? fallback : JSON.parse(value);
    } catch (e) {
      return fallback;
    }
  }

  function writeStore(key, value) {
    try {
      window.localStorage.setItem(key, JSON.stringify(value));
    } catch (e) { /* storage unavailable */ }
  }

  function csrfToken() {
    return $('meta[name="csrf-token"]').attr('content');
  }

  function escapeHtml(text) {
    return $('<div>').text(text).html();
  }

  var Kanban = {
    init: function () {
      this.container = $('#kanban-container');
      if (!this.container.length) { return; }
      this.i18n = this.container.data('i18n') || {};
      this.bindToolbar();
      this.setupBoard();
    },

    setupBoard: function () {
      this.board = $('#kanban-board');
      if (!this.board.length) { return; }
      this.storageKey = this.board.data('storage-key');
      this.laneField = this.board.data('lane-field') || '';
      this.restoreCollapsed();
      this.applySearch();
      this.applyHideEmptyLanes();
      this.updateCounts();
      this.bindBoard();
      this.setupSortable();
    },

    bindToolbar: function () {
      var self = this;
      $('#kanban-swimlane').on('change', function () { $('#query_form').trigger('submit'); });
      $('#kanban-saved-query').on('change', function () {
        var url = $(this).data('url');
        var id = $(this).val();
        window.location = url + (url.indexOf('?') >= 0 ? '&' : '?') + (id ? 'query_id=' + encodeURIComponent(id) : 'set_filter=1');
      });
      $('#kanban-search').on('input', function () { self.applySearch(); })
        .on('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); } });
      $('#kanban-hide-empty-lanes').on('change', function () {
        writeStore(self.storageKey + ':hideEmpty', this.checked);
        self.applyHideEmptyLanes();
      });
      $('#kanban-refresh').on('click', function () { self.refresh(); });
      $('#kanban-fullscreen').on('click', function () { $('body').toggleClass('kanban-fullscreen'); });
      $(document).on('keydown', function (e) {
        if (e.key === 'Escape') { $('body').removeClass('kanban-fullscreen'); }
      });
    },

    bindBoard: function () {
      var self = this;
      this.board.on('click', '.kanban-column-toggle', function () {
        var statusId = String($(this).closest('.kanban-column-header').data('status-id'));
        var collapsed = self.collapsedColumns();
        var index = collapsed.indexOf(statusId);
        if (index >= 0) { collapsed.splice(index, 1); } else { collapsed.push(statusId); }
        writeStore(self.storageKey + ':columns', collapsed);
        self.restoreCollapsed();
      });
      this.board.on('click', '.kanban-lane-toggle', function () {
        var laneId = String($(this).closest('.kanban-lane').data('lane-id'));
        var key = self.storageKey + ':lanes:' + self.board.attr('class');
        var collapsed = readStore(key, []);
        var index = collapsed.indexOf(laneId);
        if (index >= 0) { collapsed.splice(index, 1); } else { collapsed.push(laneId); }
        writeStore(key, collapsed);
        self.restoreCollapsed();
      });
    },

    collapsedColumns: function () {
      return readStore(this.storageKey + ':columns', []).map(String);
    },

    restoreCollapsed: function () {
      var collapsed = this.collapsedColumns();
      var template = [];
      this.board.find('.kanban-column-header').each(function () {
        var statusId = String($(this).data('status-id'));
        var isCollapsed = collapsed.indexOf(statusId) >= 0;
        $(this).toggleClass('kanban-collapsed', isCollapsed);
        template.push(isCollapsed ? 'var(--kanban-collapsed-width)' : 'minmax(var(--kanban-column-min), 1fr)');
      });
      this.board.find('.kanban-cell').each(function () {
        $(this).toggleClass('kanban-collapsed', collapsed.indexOf(String($(this).data('status-id'))) >= 0);
      });
      this.board.css('--kanban-template', template.join(' '));

      var lanes = readStore(this.storageKey + ':lanes:' + this.board.attr('class'), []).map(String);
      this.board.find('.kanban-lane').each(function () {
        $(this).toggleClass('kanban-lane-collapsed', lanes.indexOf(String($(this).data('lane-id'))) >= 0);
      });
    },

    applySearch: function () {
      if (!this.board || !this.board.length) { return; }
      var term = ($('#kanban-search').val() || '').toLowerCase().trim();
      this.board.find('.kanban-card').each(function () {
        var match = !term || String($(this).data('search')).indexOf(term) >= 0;
        $(this).toggleClass('kanban-filtered-out', !match);
      });
    },

    applyHideEmptyLanes: function () {
      var checkbox = $('#kanban-hide-empty-lanes');
      var hide = readStore(this.storageKey + ':hideEmpty', true);
      checkbox.prop('checked', hide);
      this.board.toggleClass('kanban-hide-empty-lanes', hide);
    },

    updateCounts: function () {
      var board = this.board;
      board.find('.kanban-column-header').each(function () {
        var header = $(this);
        var statusId = header.data('status-id');
        var cards = board.find('.kanban-cell[data-status-id="' + statusId + '"] .kanban-card');
        var wip = parseInt(header.data('wip-limit'), 10);
        var hours = 0;
        cards.each(function () { hours += parseFloat($(this).data('estimated-hours')) || 0; });
        header.find('.kanban-column-count').text(cards.length + (wip > 0 ? ' / ' + wip : ''));
        header.find('.kanban-column-hours').text(hours > 0 ? (Math.round(hours * 100) / 100) + ' h' : '');
        header.toggleClass('kanban-over-limit', wip > 0 && cards.length > wip);
      });
      board.find('.kanban-lane').each(function () {
        var count = $(this).find('.kanban-card').length;
        $(this).find('.kanban-lane-count').text(count);
        $(this).toggleClass('kanban-lane-empty', count === 0);
      });
    },

    setupSortable: function () {
      var self = this;
      if (!$.fn.sortable) { return; }
      this.board.find('.kanban-cell').sortable({
        items: '> .kanban-card.kanban-draggable',
        connectWith: '#kanban-board .kanban-cell',
        placeholder: 'kanban-card-placeholder',
        forcePlaceholderSize: true,
        tolerance: 'pointer',
        distance: 5,
        cancel: 'a, input, button',
        start: function (event, ui) { self.dragStart(ui.item); },
        stop: function (event, ui) { self.dragStop($(this), ui.item); }
      });
    },

    dragStart: function (card) {
      var self = this;
      contextMenuHideSafe();
      this.drag = {
        card: card,
        originCell: card.parent(),
        originIndex: card.index(),
        allowed: null
      };
      this.board.addClass('kanban-dragging');
      $.ajax({url: card.data('allowed-url'), dataType: 'json'}).done(function (allowed) {
        if (self.drag && self.drag.card === card) {
          self.drag.allowed = allowed;
          self.highlightTargets();
        }
      });
    },

    highlightTargets: function () {
      var self = this;
      this.board.find('.kanban-cell').each(function () {
        var allowed = self.isDropAllowed($(this));
        $(this).toggleClass('kanban-drop-allowed', allowed === true).toggleClass('kanban-drop-denied', allowed === false);
      });
    },

    // Returns null while the permissions are still loading.
    isDropAllowed: function (cell) {
      var drag = this.drag;
      if (!drag || !drag.allowed) { return null; }
      var sameStatus = String(cell.data('status-id')) === String(drag.originCell.data('status-id'));
      var sameLane = String(cell.data('lane-id')) === String(drag.originCell.data('lane-id'));
      if (sameStatus && sameLane) { return drag.allowed.rankable; }
      var statusOk = sameStatus || drag.allowed.status_ids.indexOf(parseInt(cell.data('status-id'), 10)) >= 0;
      var laneOk = sameLane || (this.laneField !== '' &&
        drag.allowed.lane_attributes.indexOf(LANE_ATTRIBUTES[this.laneField]) >= 0);
      return statusOk && laneOk;
    },

    dragStop: function (sourceCell, card) {
      var drag = this.drag;
      this.drag = null;
      this.board.removeClass('kanban-dragging');
      this.board.find('.kanban-cell').removeClass('kanban-drop-allowed kanban-drop-denied');
      if (!drag) { return; }

      var targetCell = card.parent();
      if (targetCell.is(drag.originCell) && card.index() === drag.originIndex) { return; }

      this.drag = drag;
      var allowed = this.isDropAllowed(targetCell);
      this.drag = null;
      if (allowed === false) {
        sourceCell.sortable('cancel');
        this.showError(this.i18n.error, card);
        return;
      }
      this.updateCounts();
      this.sendMove(drag, card, targetCell);
    },

    sendMove: function (drag, card, targetCell) {
      var self = this;
      var data = {
        lock_version: card.data('lock-version'),
        board_project_id: this.board.data('board-project-id'),
        order: targetCell.children('.kanban-card').map(function () { return $(this).data('id'); }).get()
      };
      if (String(targetCell.data('status-id')) !== String(card.data('status-id'))) {
        data.status_id = targetCell.data('status-id');
      }
      if (this.laneField && String(targetCell.data('lane-id')) !== String(drag.originCell.data('lane-id'))) {
        data.lane_field = this.laneField;
        data.lane_value = targetCell.data('lane-id');
      }
      card.addClass('kanban-saving');
      $.ajax({
        url: card.data('move-url'),
        type: 'POST',
        data: data,
        dataType: 'json',
        headers: {'X-CSRF-Token': csrfToken()}
      }).done(function (response) {
        var fresh = $(response.card);
        card.replaceWith(fresh);
        self.applySearch();
        self.updateCounts();
        fresh.addClass('kanban-just-moved');
        window.setTimeout(function () { fresh.removeClass('kanban-just-moved'); }, 1200);
        self.hideError();
      }).fail(function (xhr) {
        card.removeClass('kanban-saving');
        self.revert(drag, card);
        var message = (xhr.responseJSON && xhr.responseJSON.error) || self.i18n.error;
        self.showError(message, card);
      });
    },

    revert: function (drag, card) {
      var siblings = drag.originCell.children('.kanban-card').not(card);
      if (drag.originIndex >= siblings.length) {
        drag.originCell.append(card);
      } else {
        siblings.eq(drag.originIndex).before(card);
      }
      this.updateCounts();
    },

    showError: function (message, card) {
      var flash = $('#kanban-flash');
      var html = escapeHtml(message);
      if (card) {
        var link = card.find('.kanban-card-id').attr('href');
        html += ' <a href="' + escapeHtml(link) + '">' + escapeHtml(this.i18n.open_issue) + '</a>';
      }
      flash.removeClass('notice').addClass('error').html(html).show();
    },

    hideError: function () {
      $('#kanban-flash').hide().empty();
    },

    refresh: function () {
      var self = this;
      var button = $('#kanban-refresh');
      button.addClass('ajax-loading');
      $.ajax({url: button.data('url'), dataType: 'html'}).done(function (html) {
        self.container.html(html);
        self.setupBoard();
      }).always(function () {
        button.removeClass('ajax-loading');
      });
    }
  };

  function contextMenuHideSafe() {
    if (typeof contextMenuHide === 'function') { contextMenuHide(); }
  }

  var Settings = {
    init: function () {
      var table = $('.kanban-settings-columns tbody');
      if (!table.length || !$.fn.sortable) { return; }
      table.sortable({
        handle: '.kanban-sort-handle',
        axis: 'y',
        update: function () {
          table.find('tr').each(function (index) { $(this).find('.kanban-position').val(index); });
        }
      });
    }
  };

  $(function () {
    Kanban.init();
    Settings.init();
  });
})(jQuery);
