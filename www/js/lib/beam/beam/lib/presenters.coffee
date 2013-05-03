define ["jquery"], ($) ->
  exports = {}


  class exports.Presenter
    constructor: (@parent, @view, @services, args...) ->
      @_children = []
      @parent?._children.push(this)

      @initialize.apply(this, args)

    initialize: ->

    dispose: ->
      children = @_children
      @_children = []
      for child in children
        child.dispose()
      @view.dispose()
      if @parent?
        if (i = @parent._children.indexOf(this)) != -1
          @parent._children.splice(i, 1)
        @parent = null


  class exports.Page extends exports.Presenter
    suspend: ->
      true

    resume: ->
      (new $.Deferred()).resolve()


  class exports.Collection extends exports.Presenter
    initialize: (@itemPresenter) ->
      @_childrenVisible = 0
      @_defaultFilter =
        predicate: ->
          true
        onTotalChanged: ->
          undefined
      @_filter = @_defaultFilter

    # Public API
    applyFilter: (filter) ->
      @_filter = $.extend({}, @_defaultFilter, filter)

      predicate = @_filter.predicate
      @_childrenVisible = 0
      for item in @_children
        visible = predicate(item)
        item.view.setVisible(visible)
        if visible then @_childrenVisible++

      @view.onViewportChanged()

      @_filter.onTotalChanged(@_childrenVisible)

    reset: (objects) ->
      @_childrenVisible = 0
      @_filter.onTotalChanged(0)

      children = @_children.splice(0, @_children.length)
      @view.clear().done =>
        for item in children
          item.dispose()
      @add(objects)

    add: (objects, position = 'end') ->
      if objects.length == 0
        return
      if position == 'end'
        position = @_children.length
      views = []
      childrenSpliceArgs = [ position, 0 ]
      predicate = @_filter.predicate
      for object, i in objects
        view = new @view.itemView(null)
        views.push(view)
        item = new @itemPresenter(null, view, @services, object)
        item.parent = this
        childrenSpliceArgs.push(item)
        visible = predicate(item)
        view.setVisible(visible)
        if visible then @_childrenVisible++
      @_children.splice.apply(@_children, childrenSpliceArgs)
      @view.add(views, position)
      @_filter.onTotalChanged(@_childrenVisible)

    remove: (position) ->
      [item] = @_children.splice(position, 1)
      if item.view.isVisible()
        @_childrenVisible--
        @_filter.onTotalChanged(@_childrenVisible)
      @view.remove(item.view, position).done ->
        item.dispose()

    move: (oldPosition, newPosition) ->
      if newPosition == oldPosition then return
      [item] = @_children.splice(oldPosition, 1)
      @_children.splice(newPosition, 0, item)
      @view.move(item.view, oldPosition, newPosition)

    sort: (compare) ->
      sorted = @_children.slice(0).sort(compare)
      for item, i in sorted
        oldPosition = @_children.indexOf(item)
        newPosition = i
        if newPosition > oldPosition
          newPosition--
        @move(oldPosition, newPosition)

    # Utility API
    forEach: (callback) ->
      for item, i in @_children
        if callback(item, i) == 'stop'
          return false
      true

    map: (callback) ->
      result = []
      for item, i in @_children
        result.push(callback(item, i))
      result

    find: (predicate) ->
      for item, i in @_children
        if predicate(item, i)
          return item
      undefined

    removeMatching: (predicate) ->
      remove = []
      for item, i in @_children
        if predicate(item, i)
          remove.push(i - remove.length)
      for pos in remove
        @remove(pos)
      remove.length > 0

    at: (position) ->
      @_children[position]

    size: ->
      @_children.length


  class exports.CappedCollection extends exports.Presenter
    initialize: (@itemPresenter, @cap, @anchor) ->
      @_objects = []

    # Public API
    setCap: (@cap) ->
      @_adapt()

    reset: (objects) ->
      @_objects = []
      children = @_children.splice(0, @_children.length)
      @view.clear().done =>
        for item in children
          item.dispose()
      @add(objects)

    add: (objects, position = 'end') ->
      if position == 'end'
        position = @_objects.length

      args = objects.slice(0)
      args.splice(0, 0, position, 0)
      @_objects.splice.apply(@_objects, args)

      if @anchor == 'right'
        windowSize = @_children.length
        windowStart = @_objects.length - windowSize
        windowEnd = @_objects.length

        objectsStart = position
        objectsEnd = position + objects.length

        offset = objectsStart - windowStart + 1
        if objects.length > 0 and offset > 0
          addedViews = @_insertPresenters(offset, objectsStart, objectsEnd)

          removalSize = Math.max(@_children.length - @cap, 0)
          @_remove(0, removalSize)

          @view.add(addedViews, offset - removalSize)
        else
          @_adapt()
      else
        throw 'not-implemented'

    remove: (position) ->
      if @anchor == 'right'
        windowSize = @_children.length
        windowStart = @_objects.length - windowSize
        windowEnd = @_objects.length

        @_objects.splice(position, 1)

        offset = position - windowStart
        if windowSize > 0 and offset >= 0
          @_remove(offset, 1)

        @_adapt()
      else
        throw 'not-implemented'

    # Utility API
    forEach: (callback) ->
      for object, i in @_objects
        if callback(object, i) == 'stop'
          return false
      true

    find: (predicate) ->
      for object, i in @_objects
        if predicate(object, i)
          return object
      undefined

    removeMatching: (predicate) ->
      remove = []
      for object, i in @_objects
        if predicate(object, i)
          remove.push(i - remove.length)
      for pos in remove
        @remove(pos)
      remove.length > 0

    at: (position) ->
      @_objects[position]

    size: ->
      @_objects.length

    # Internals
    _adapt: ->
      available = @cap - @_children.length
      if available > 0
        unconsumed = @_objects.length - @_children.length
        if unconsumed > 0
          consumable = Math.min(unconsumed, available)
          objectsStart = unconsumed - consumable
          objectsEnd = objectsStart + consumable
          @view.add(@_insertPresenters(0, objectsStart, objectsEnd), 0)
      else if available < 0
        @_remove(0, -available)

    _insertPresenters: (position, objectsStart, objectsEnd) ->
      views = []
      childrenSpliceArgs = [ position, 0 ]
      for object in @_objects[objectsStart...objectsEnd]
        view = new @view.itemView(null)
        views.push(view)
        presenter = new @itemPresenter(null, view, @services, object)
        presenter.parent = this
        childrenSpliceArgs.push(presenter)
      @_children.splice.apply(@_children, childrenSpliceArgs)
      views

    _remove: (position, count) ->
      remove = (presenter) =>
        @view.remove(presenter.view, position).done ->
          presenter.dispose()
      for presenter in @_children.splice(position, count)
        remove(presenter)


  class exports.LazyCollection extends exports.Presenter
    initialize: (@itemPresenter) ->
      @_objects = []
      @_presenters = {}
      @view.onViewportChange(@_onViewportChange)

    dispose: ->
      super
      @_clear()

    # Public API
    reset: (objects) ->
      @_clear()
      @_add(objects)

    add: (objects, position = 'end') ->
      if position == 'end'
        position = @_objects.length
      @_add(objects, position)

    remove: (position) ->
      @_remove(position)

    move: (oldPosition, newPosition) ->
      @_move(oldPosition, newPosition)

    # Utility API
    forEach: (callback) ->
      for object, i in @_objects
        if callback(object, i) == 'stop'
          return false
      true

    forEachPresenter: (callback) ->
      for own pos, presenter of @_presenters
        if callback(presenter, pos) == 'stop'
          return false
      true

    find: (predicate) ->
      for object, i in @_objects
        if predicate(object, i)
          return object
      undefined

    removeMatching: (predicate) ->
      remove = []
      for object, i in @_objects
        if predicate(object, i)
          remove.push(i - remove.length)
      for pos in remove
        @remove(pos)
      remove.length > 0

    at: (position) ->
      @_objects[position]

    size: ->
      @_objects.length

    # Internals
    _clear: ->
      @_objects = []
      presenters = @_presenters
      @_presenters = {}
      @view.clear().done ->
        for own pos, presenter of presenters
          presenter.dispose()

    _add: (objects, position) ->
      args = objects.slice(0)
      args.splice(0, 0, position, 0)
      @_objects.splice.apply(@_objects, args)

      presenters = {}
      for own pos, presenter of @_presenters
        pos = parseInt(pos)
        if pos >= position
          presenters[pos + objects.length] = presenter
        else
          presenters[pos] = presenter
      @_presenters = presenters

      @view.allocate(position, objects.length).done =>
        @_onViewportChange()

    _remove: (position) ->
      @_objects.splice(position, 1)

      presenters = {}
      remove = null
      for own pos, presenter of @_presenters
        pos = parseInt(pos)
        if pos == position
          remove = presenter
        else if pos >= position + 1
          presenters[pos - 1] = presenter
        else
          presenters[pos] = presenter
      @_presenters = presenters

      @view.deallocate(position, 1).done =>
        remove?.dispose()
        @_onViewportChange()

    _move: (oldPosition, newPosition) ->
      if newPosition == oldPosition then return

      if not @view.contains(oldPosition) and not @view.contains(newPosition)
        object = @_objects[oldPosition]
        @_remove(oldPosition)
        @_add([object], newPosition)
      else
        [object] = @_objects.splice(oldPosition, 1)
        @_objects.splice(newPosition, 0, object)

        presenter = @_presenters[oldPosition]
        createdPresenter = null
        if not presenter?
          presenter = new @itemPresenter(null, new @view.itemView(null), @services, object)
          presenter.parent = this
          @_presenters[oldPosition] = presenter
          createdPresenter = presenter
        view = presenter.view

        presenters = {}
        for own pos, presenter of @_presenters
          pos = parseInt(pos)
          if pos == oldPosition
            presenters[newPosition] = presenter
          else if newPosition > oldPosition and pos > oldPosition and pos <= newPosition
            presenters[pos - 1] = presenter
          else if newPosition < oldPosition and pos >= newPosition and pos < oldPosition
            presenters[pos + 1] = presenter
          else
            presenters[pos] = presenter
        @_presenters = presenters

        @view.move(view, oldPosition, newPosition).done =>
          if createdPresenter?.calibrate?
            window.setTimeout((() -> createdPresenter.calibrate()), 0)
          @_onViewportChange()

    _onViewportChange: =>
      viewport = @view.getViewport()

      wipe = (pos) =>
        presenter = @_presenters[pos]
        if @view.hasLocked(presenter.view)
          return
        delete @_presenters[pos]
        @view.wipe(pos).done ->
          presenter.dispose()
      invisible = if not viewport?
        parseInt(pos) for own pos, presenter of @_presenters
      else
        parseInt(pos) for own pos, presenter of @_presenters when (pos < viewport[0] or pos >= viewport[1])
      for pos in invisible
        wipe(pos)

      if viewport?
        [startPos, endPos] = viewport

        batchStartPos = null
        batch = []
        flush = =>
          if batch.length == 0 then return
          presenters = batch
          batch = []
          views = (presenter.view for presenter in presenters)
          @view.fill(batchStartPos, views).done ->
            if presenters[0].calibrate?
              window.setTimeout((() ->
                for presenter in presenters
                  presenter.calibrate()
              ), 0)

        for object, i in @_objects[startPos...endPos]
          pos = startPos + i
          if pos not of @_presenters
            presenter = new @itemPresenter(null, new @view.itemView(null), @services, object)
            presenter.parent = this
            @_presenters[pos] = presenter
            if batch.length == 0
              batchStartPos = pos
            batch.push(presenter)
          else
            flush()
        flush()


  class exports.FilteredLazyCollection extends exports.LazyCollection
    initialize: ->
      super
      @_allObjects = []
      @_filter = null

    # Public API
    applyFilter: (filter) ->
      if filter?
        @_filter = $.extend({}, {
          onTotalChanged: ->
            undefined
        }, filter)
      else
        @_filter = null
      @reset(@_allObjects)

    reset: (objects) ->
      @_allObjects = objects.slice(0)
      if @_filter?
        predicate = @_filter.predicate
        filteredObjects = (object for object in @_allObjects when predicate(object))
        super(filteredObjects)
        @_filter.onTotalChanged(filteredObjects.length)
      else
        super(@_allObjects)

    add: (objects, position = 'end') ->
      if position == 'end'
        position = @_objects.length

      args = objects.slice(0)
      args.splice(0, 0, position, 0)
      @_allObjects.splice.apply(@_allObjects, args)

      if @_filter?
        @reset(@_allObjects)
      else
        super

    remove: (position) ->
      @_allObjects.splice(position, 1)

      if @_filter?
        @reset(@_allObjects)
      else
        super

    move: (oldPosition, newPosition) ->
      [object] = @_allObjects.splice(oldPosition, 1)
      @_allObjects.splice(newPosition, 0, object)

      if @_filter?
        @reset(@_allObjects)
      else
        super

    # Utility API
    forEach: (callback) ->
      for object, i in @_allObjects
        if callback(object, i) == 'stop'
          return false
      true

    find: (predicate) ->
      for object, i in @_allObjects
        if predicate(object, i)
          return object
      undefined

    removeMatching: (predicate) ->
      remove = []
      for object, i in @_allObjects
        if predicate(object, i)
          remove.push(i - remove.length)
      for pos in remove
        @remove(pos)
      remove.length > 0

    at: (position) ->
      @_allObjects[position]

    size: ->
      @_allObjects.length


  return exports
