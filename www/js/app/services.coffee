define ["jquery", "beam/main"], ($, beam) ->
  services = {}


  class services.Frida extends beam.services.Service
    initialize: ->
      @_client = new Client()
      @capture = new Capture(this, @services.bus)

    start: ->
      @on('detached', @_onDetached)
      @on('message', @_onMessage)

    on: ->
      @_client.on.apply(@_client, arguments)

    enumerateDevices: ->
      @_client.request('.enumerate-devices')

    enumerateProcesses: (deviceId) ->
      @_client.request('.enumerate-processes', {
        device:
          id: deviceId
      })

    _onDetached: (device, pid) =>
      @capture._onDetached(device, pid)

    _onMessage: (device, pid, message, data) =>
      @capture._onMessage(device, pid, message, data)

    class Capture extends beam.Events
      initialize: (@frida, @bus) ->
        @_current = null
        @streams = []

      open: (device, pid) ->
        if @_current?
          throw new Error("capture already open")
        @_current =
          device: device
          pid: pid
        @frida._client.request('.attach', {
          device: device,
          pid: pid
        })

      close: (device, pid) ->
        d = $.Deferred()
        if @_current?
          if device != @_current.device or pid != @_current.pid
            throw new Error("invalid device or pid")
          @frida._client.request('.detach', {
            device: device,
            pid: pid
          }).always =>
            @_close()
            d.resolve()
        else
          d.resolve()
        d

      pull: (fields) ->
        @frida._client.request('.post-message', {
          type: 'streams:pull',
          payload: fields
        })

      _close: ->
        @_current = null
        @streams = []

      _findStreamById: (id) ->
        for stream in @streams
          if stream.get('id') == id
            return stream
        return null

      _onDetached: (device, pid) =>
        if device == @_current?.device and pid == @_current?.pid
          for stream in @streams
            @_trigger('destroyed', stream)
          @_close()
          @_trigger('closed', device, pid)

      _postMessage: (message) ->
        @frida._plugin.postMessage(@_current.device, @_current.pid, message)

      _onMessage: (device, pid, transportMessage, data) =>
        if transportMessage.type == 'send'
          message = transportMessage.payload
          switch message.type
            when 'streams:add'
              stream = new Stream(message.payload, this, @bus)
              @streams.push(stream)
              @_trigger('added', stream)
            when 'streams:update'
              for own id, updates of message.payload
                id = parseInt(id)
                stream = @_findStreamById(id)
                if stream?
                  stream._update(updates)
                  @_trigger('updated', stream, updates)
            else
              if (id = message.stream_id)?
                @_findStreamById(id)?._onMessage(message, data)
              else
                console.log(message)
        else
          console.log("Got #{transportMessage.type} message from pid #{pid}:")
          console.log(transportMessage)

      class Model extends beam.Events
        initialize: (object) ->
          @_properties = $.extend({}, object)

        get: (property) ->
          @_properties[property]

        _update: (updates) ->
          if updates == null
            @_properties = {}
            @_trigger('deleted', updates)
          else
            @_properties = $.extend(@_properties, updates)
            @_trigger('updated', updates)

      class Stream extends Model
        initialize: (object, @capture, @bus) ->
          super(object)
          @events = []

        mute: ->
          @capture._postMessage({
            type: 'stream:mute'
            stream_id: @get('id')
            payload: {}
          })

        _onMessage: (message, data) ->
          switch message.type
            when 'stream:event'
              extra = {}
              if data?
                extra.data = data
              event = $.extend({}, message.payload, extra)
              @events.push(event)
              @_trigger('appended', event)
              @bus.post('stream:appended', {
                stream: this
                event: event
              }, this)

  class Client
    constructor: ->
      @_pending = {}
      @_nextRequestId = 1

      @_socket = io("http://localhost:3000/")
      @_socket.on('stanza', @_onStanza)

      @_listeners = {}

    request: (name, payload = {}) ->
      d = $.Deferred()
      id = @_nextRequestId++
      request =
        id: id
        name: name
        payload: payload
      @_pending[id] = d
      @_socket.emit('stanza', request)
      d

    on: (event, callback) ->
      listeners = @_listeners[event] or []
      listeners.push(callback)
      @_listeners[event] = listeners

    _onStanza: (stanza) =>
      if (id = stanza.id)?
        d = @_pending[id]
        delete @_pending[id]
        switch stanza.name
          when '+result'
            d.resolve(stanza.payload)
          when '+error'
            d.reject(stanza.payload)
      else:
        (listeners = @_listeners[stanza.name.substr(1)] or []).forEach (callback) ->
          callback(stanza.payload)


  return services
