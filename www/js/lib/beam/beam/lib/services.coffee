define ["cs!./events"], (events) ->
  exports = {}


  class exports.Service
    constructor: (services, args...) ->
      @services = services
      @initialize.apply(this, args)

    initialize: ->

    start: ->

    dispose: ->


  class exports.MessageBus extends exports.Service
    initialize: ->
      @_events = new events.Events()

    on: (type, callback) ->
      @_events.on(type, callback)

    off: (type, callback) ->
      @_events.off(type, callback)

    post: (type, message, sender) ->
      @_events._trigger(type, message, sender)


  return exports
