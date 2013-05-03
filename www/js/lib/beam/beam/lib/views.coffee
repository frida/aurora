define ["jquery"], ($) ->
  exports = {}


  class exports.View
    @partials: {}

    constructor: (@parent, args...) ->
      @_children = []
      @parent?._children.push(this)

      @initialize.apply(this, args)

    initialize: ->

    dispose: ->
      children = @_children
      @_children = []
      for child in children
        child.dispose()
      @element.remove()
      if @parent?
        if (i = @parent._children.indexOf(this)) != -1
          @parent._children.splice(i, 1)
        @parent = null

    isVisible: ->
      @element.is(':visible')

    setVisible: (value) ->
      @element.toggle(value)

    setText: (key, value, link = null) ->
      el = @element.find("[data-bind='#{key}']")
      el.text(value)
      if link? then el.attr('href', link)

    setHtml: (key, value) ->
      @element.find("[data-bind='#{key}']").html(value)

    triggerAction: (action) ->
      @element.trigger('soundrop-action', [action])

    onAction: (handler) ->
      @element.on 'soundrop-action', (ev, action) ->
        handler(action)

    # protected
    _loadPartial: (id) ->
      partials = exports.View.partials
      if not (element = partials[id])?
        element = $($("#partial-#{id}").html())
        top = window
        if top.i18n?
          elements = element.find("[data-i18n]")
          if element.data('i18n')
            elements = elements.andSelf()
          elements.each () ->
            child = $(this)
            [catalog, key] = child.data('i18n').split("/")
            child.html(top.i18n.format(catalog, key, {}))

          elements = element.find("[data-i18n-placeholder]")
          if element.data('i18n-placeholder')
            elements = elements.andSelf()
          elements.each () ->
            child = $(this)
            [catalog, key] = child.data('i18n-placeholder').split("/")
            child.attr('placeholder', top.i18n.format(catalog, key, {}))
        partials[id] = element
      element.clone()


  class exports.Collection extends exports.View
    initialize: (@element, @itemView) ->
      @_pending = []
      @_processing = false

    onViewportChanged: ->

    clear: ->
      deferred = $.Deferred()
      @_schedule (complete) =>
        for view in @_children
          view.dispose()
        @_children = []
        deferred.resolve()
        complete()
      deferred

    add: (views, position) ->
      deferred = $.Deferred()
      @_schedule (complete) =>
        elements = []
        for view, i in views
          @_children.splice(position + i, 0, view)
          elements.push(view.element.get(0))
        @_add views, elements, position, ->
          deferred.resolve()
          complete()
      deferred

    remove: (view, position) ->
      deferred = $.Deferred()
      @_schedule (complete) =>
        @_children.splice(position, 1)
        @_remove view, position, ->
          deferred.resolve()
          complete()
      deferred

    move: (view, oldPosition, newPosition, callback) ->
      deferred = $.Deferred()
      @_schedule (complete) =>
        @_children.splice(oldPosition, 1)
        @_children.splice(newPosition, 0, view)
        @_move view, oldPosition, newPosition, ->
          deferred.resolve()
          complete()
      deferred

    _schedule: (operation) ->
      @_pending.push(operation)
      if not @_processing
        @_processing = true
        @_processPending()

    _processPending: =>
      if @_pending.length == 0
        @_processing = false
        return
      operation = @_pending.shift()
      operation(@_processPending)

    # Override these to do custom transitions
    _add: (views, elements, position, callback) ->
      if (position + views.length) == @_children.length
        @element.append(elements)
        callback()
      else
        nextElement = @_children[position + views.length].element
        $(elements).insertBefore(nextElement)
        callback()

    _remove: (view, position, callback) ->
      view.element.remove()
      callback()

    _move: (view, oldPosition, newPosition, callback) ->
      view.element.detach()
      if newPosition == @_children.length - 1
        view.element.insertAfter(@_children[newPosition - 1].element)
      else
        view.element.insertBefore(@_children[newPosition + 1].element)
      callback()


  class exports.LazyCollection extends exports.View
    initialize: (@element, @itemView) ->
      @_pending = []
      @_processing = false
      @_size = 0
      @_views = {}
      @_lockedViews = []
      @_viewport = [ -1, -1 ]
      @_onViewportChange = null

      @element.css('position', 'relative')

      $(window).on('resize', @_scheduleUpdateViewport)
      $(window).on('scroll', @_scheduleUpdateViewport)

    dispose: ->
      super
      $(window).off('resize', @_scheduleUpdateViewport)
      $(window).off('scroll', @_scheduleUpdateViewport)

    getViewport: ->
      if @_viewport[0]? then @_viewport else null

    syncViewport: ->
      @_scheduleUpdateViewport()

    contains: (position) ->
      if @_viewport?
        position >= @_viewport[0] and position < @_viewport[1]
      else
        false

    at: (position) ->
      @_views[position]

    onViewportChange: (handler) ->
      @_onViewportChange = handler

    lock: (view) ->
      @_lockedViews.push(view)

    unlock: (view) ->
      if (pos = @_lockedViews.indexOf(view)) >= 0
        @_lockedViews.splice(pos, 1)

    hasLocked: (view) ->
      @_lockedViews.indexOf(view) >= 0

    clear: ->
      result = $.Deferred()
      @_schedule (complete) =>
        @_size = 0

        for own pos, view of @_views
          view.element.detach()
        @_views = {}
        @_lockedViews = []

        @element.css('height', 0)

        @_updateViewport()

        result.resolve()
        complete()
      result.promise()

    allocate: (startPos, size) ->
      result = $.Deferred()
      @_schedule (complete) =>
        @_size += size

        @element.css('height', @_size * @itemView.Height)

        views = {}
        for own pos, view of @_views
          pos = parseInt(pos)
          if pos >= startPos
            newPos = pos + size
            view.element.css('top', newPos * @itemView.Height)
            views[newPos] = view
          else
            views[pos] = view
        @_views = views

        @_updateViewport()

        result.resolve()
        complete()
      result.promise()

    deallocate: (startPos, size) ->
      result = $.Deferred()
      @_schedule (complete) =>
        @_size -= size

        removeOperation = $.Deferred()
        remove = []
        for own pos, view of @_views
          pos = parseInt(pos)
          if pos >= startPos and pos < startPos + size
            remove.push(view)
        removeNext = =>
          if remove.length == 0
            removeOperation.resolve()
            return
          view = remove.shift()
          @unlock(view)
          @_remove(view, removeNext)
        removeNext()

        removeOperation.done =>
          views = {}
          for own pos, view of @_views
            pos = parseInt(pos)
            if pos >= startPos and pos < startPos + size
              # Skip
            else if pos >= startPos + size
              newPos = pos - size
              view.element.css('top', newPos * @itemView.Height)
              views[newPos] = view
            else
              views[pos] = view
          @_views = views

          @element.css('height', @_size * @itemView.Height)

          @_updateViewport()

          result.resolve()
          complete()
      result.promise()

    fill: (startPos, views) ->
      result = $.Deferred()
      @_schedule (complete) =>
        elements = []
        for view, i in views
          pos = startPos + i
          view.element.css({
            position: 'absolute'
            top: pos * @itemView.Height
            right: 0
            left: 0
          })
          @_views[pos] = view
          elements.push(view.element.get(0))
        @_add views, elements, ->
          result.resolve()
          complete()
      result.promise()

    wipe: (position) ->
      result = $.Deferred()
      @_schedule (complete) =>
        view = @_views[position]
        view.element.detach()
        delete @_views[position]
        result.resolve()
        complete()
      result.promise()

    move: (existingView, oldPosition, newPosition) ->
      result = $.Deferred()
      @_schedule (complete) =>
        if oldPosition not of @_views
          @_views[oldPosition] = existingView
          existingView.element.css({
            position: 'absolute'
            top: oldPosition * @itemView.Height
            right: 0
            left: 0
          })
          @element.append(existingView.element)

        @_moveOut existingView, =>
          views = {}
          for own pos, view of @_views
            pos = parseInt(pos)
            if pos == oldPosition
              views[newPosition] = view
            else if newPosition > oldPosition and pos > oldPosition and pos <= newPosition
              newPos = pos - 1
              view.element.css('top', newPos * @itemView.Height)
              views[newPos] = view
            else if newPosition < oldPosition and pos >= newPosition and pos < oldPosition
              newPos = pos + 1
              view.element.css('top', newPos * @itemView.Height)
              views[newPos] = view
            else
              views[pos] = view
          @_views = views

          existingView.element.css('top', newPosition * @itemView.Height)

          @_moveIn existingView, ->
            result.resolve()
            complete()
      result.promise()

    scrollTo: (position) ->
      result = $.Deferred()
      @_schedule (complete) =>
        $(window).scrollTop(@element.offset().top + (position * @itemView.Height))
        result.resolve()
        complete()
      result.promise()

    _scheduleUpdateViewport: =>
      @_schedule(@_processUpdateViewport)

    _processUpdateViewport: (complete) =>
      @_updateViewport()
      complete()

    _updateViewport: ->
      if @_pending.length != 0
        # Never update viewport if operations are pending
        @_pending = (operation for operation in @_pending when operation != @_processUpdateViewport)
        @_scheduleUpdateViewport()
        return
      viewport = @_computeViewport()
      if viewport[0] != @_viewport[0] or viewport[1] != @_viewport[1]
        @_viewport = viewport
        @_onViewportChange?()

    _computeViewport: ->
      w = $(window)
      threshold = 2 * @itemView.Height
      viewportTop = Math.max(w.scrollTop() - threshold, 0)
      viewportBottom = w.scrollTop() + w.height() + threshold
      collectionHeight = @element.height()
      collectionTop = @element.offset().top
      collectionBottom = collectionTop + collectionHeight
      if viewportBottom > collectionTop and viewportTop < collectionBottom
        offsetTop = Math.max(viewportTop - collectionTop, 0)
        offsetBottom = Math.min(viewportBottom - collectionTop, collectionHeight)
        startPosition = Math.floor(offsetTop / @itemView.Height)
        endPosition = Math.floor((offsetBottom - 1) / @itemView.Height) + 1
        [startPosition, endPosition]
      else
        [null, null]

    _schedule: (operation) ->
      @_pending.push(operation)
      if not @_processing
        @_processing = true
        @_processPending()

    _processPending: =>
      if @_pending.length == 0
        @_processing = false
        return
      operation = @_pending.shift()
      operation(@_processPending)

    # Override these to do custom transitions
    _add: (views, elements, callback) ->
      @element.append(elements)
      callback()

    _remove: (view, callback) ->
      view.element.detach()
      callback()

    _moveOut: (view, callback) ->
      callback()

    _moveIn: (view, callback) ->
      callback()


  class exports.Picture extends exports.View
    initialize: (@element, @size = 'small') ->
      @currentUrl = null
      @element.wrapInner($(document.createElement('div')).addClass("display-picture-inner"))
      @_inner = @element.find(".display-picture-inner")

    setTitle: (value) ->
      @element.attr('title', value)

    setSource: (value) ->
      url = if value?.indexOf('http') == 0 then "#{value}?type=#{@size}" else value
      if url != @currentUrl
        @currentUrl = url
        if url
          @_inner.css('background-image', "url(#{url})")
        else
          @_inner.css('background-image', null)


  return exports
