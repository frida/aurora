define [], ->
  exports = {}


  class exports.Events
    constructor: ->
      @initialize.apply(this, arguments)

    initialize: ->

    on: (event, callback) ->
      callbacks = @hasOwnProperty('_callbacks') and @_callbacks or= {}
      callbacks[event] or= []
      callbacks[event].push(callback)
      callback

    off: (event, callback) ->
      callbacks = @_callbacks?[event]
      unless callbacks
        return this

      unless callback
        delete @_callbacks[event]
        return this

      for cb, i in callbacks when cb is callback
        callbacks = callbacks.slice()
        callbacks.splice(i, 1)
        @_callbacks[event] = callbacks
        break
      callback

    _trigger: (event, args...) ->
      callbacks = @hasOwnProperty('_callbacks') and @_callbacks?[event]
      unless callbacks
        return false

      for callback in callbacks
        callback.apply(this, args)
      true


  return exports
