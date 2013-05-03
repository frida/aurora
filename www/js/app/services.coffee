define ["jquery", "beam/main"], ($, beam) ->
  services = {}


  class services.Frida extends beam.services.Service
    initialize: ->
      @_plugin = $("#frida").get(0)
      @capture = new Capture(this, @services.bus)

    start: ->
      @_plugin.addEventListener('detach', @_onDetach)
      @_plugin.addEventListener('message', @_onMessage)

    addEventListener: ->
      @_plugin.addEventListener.apply(@_plugin, arguments)

    enumerateDevices: ->
      @_plugin.enumerateDevices.apply(@_plugin, arguments)

    enumerateProcesses: ->
      @_plugin.enumerateProcesses.apply(@_plugin, arguments)

    _onDetach: (device, pid) =>
      @capture._onDetach(device, pid)

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
        rawScript = Capture.Script.toString()
        rawBody = rawScript.substring(rawScript.indexOf("{") + 1, rawScript.lastIndexOf("return"))
        @frida._plugin.attachTo(device, pid, rawBody)

      close: (device, pid) ->
        result = $.Deferred()
        if @_current?
          if device != @_current.device or pid != @_current.pid
            throw new Error("invalid device or pid")
          @frida._plugin.detachFrom(device, pid).always =>
            @_close()
            result.resolve()
        else
          result.resolve()
        result

      pull: (fields) ->
        @_postMessage({
          type: 'streams:pull'
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

      _onDetach: (device, pid) =>
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

      @Script: ->
        streams = []
        lastStreamId = 1
        lastReadTimestamp = null

        createStream = (fd) ->
          stream =
            id: lastStreamId++
            status: 'normal'
            fd: fd
            type: Socket.type(fd) or 'file'
            localAddress: Socket.localAddress(fd)
            peerAddress: Socket.peerAddress(fd)
            stats:
              read:
                buffers: 0
                bytes: 0
              write:
                buffers: 0
                bytes: 0
              drop:
                buffers: 0
                bytes: 0
            dirty: false
          streams.push(stream)
          return stream

        findStreamById = (id) ->
          for stream in streams
            if stream.id == id
              return stream
          return null

        getStreamByFileDescriptor = (fd) ->
          for stream in streams
            if stream.fd == fd
              return stream
          stream = createStream(fd)
          send({
            type: 'streams:add'
            payload:
              id: stream.id
              status: stream.status
              fd: stream.fd
              type: stream.type
              localAddress: stream.localAddress
              peerAddress: stream.peerAddress
              stats: stream.stats
          })
          return stream

        updateStream = (id, updates) ->
          stream = findStreamById(id)
          if stream?
            for k, v of updates
              stream[k] = v
            allUpdates = {}
            allUpdates[id] = updates
            send({
              type: 'streams:update'
              payload: allUpdates
            })

        receiveMute = ->
          recv 'stream:mute', (message) ->
            updateStream(message.stream_id, {
              status: 'muted'
            })
            receiveMute()
        receiveMute()

        receivePull = ->
          recv 'streams:pull', (message) ->
            fields = message.payload
            updates = {}
            for stream in streams
              if stream.status == 'muted' or not stream.dirty
                continue
              stream.dirty = false
              u = {}
              for field in fields
                u[field] = stream[field]
              updates[stream.id] = u
            send({
              type: 'streams:update'
              payload: updates
            })
            receivePull()
        receivePull()


        AF_INET = 2
        isWindows = false
        netLibrary = 'libSystem.B.dylib'
        connectImpl = Module.findExportByName(netLibrary, 'connect$UNIX2003')
        if not connectImpl?
          connectImpl = Module.findExportByName(netLibrary, 'connect')
        if not connectImpl?
          netLibrary = 'ws2_32.dll'
          connectImpl = Module.findExportByName(netLibrary, 'connect')
          isWindows = connectImpl?
        if connectImpl?
          Interceptor.attach connectImpl,
            onEnter: (args) ->
              sockAddr = args[1]
              if isWindows
                family = Memory.readU8(sockAddr)
              else
                family = Memory.readU8(sockAddr.add(1))
              if family == AF_INET
                fd = args[0].toInt32()
                stream = getStreamByFileDescriptor(fd)
                if stream.status != 'muted'
                  ip =
                    Memory.readU8(sockAddr.add(4)) + "." +
                    Memory.readU8(sockAddr.add(5)) + "." +
                    Memory.readU8(sockAddr.add(6)) + "." +
                    Memory.readU8(sockAddr.add(7))
                  port = (Memory.readU8(sockAddr.add(2)) << 8) | Memory.readU8(sockAddr.add(3))
                  updateStream(stream.id, {
                    peerAddress:
                      ip: ip
                      port: port
                  })
                  send({
                    type: 'stream:event'
                    stream_id: stream.id
                    payload:
                      type: 'connect'
                      properties:
                        ip: ip
                        port: port
                  })

        readImpl = Module.findExportByName(netLibrary, 'read$UNIX2003')
        if not readImpl?
          readImpl = Module.findExportByName(netLibrary, 'read')
        if readImpl?
          Interceptor.attach readImpl,
            onEnter: (args) ->
              this.fd = args[0].toInt32()
              this.buf = args[1]
            onLeave: (retval) ->
              if retval.toInt32() > 0
                stream = getStreamByFileDescriptor(this.fd)
                if stream.status != 'muted'
                  now = new Date()
                  if not lastReadTimestamp? or now - lastReadTimestamp >= 250
                    send({
                      type: 'stream:event'
                      stream_id: stream.id
                      payload:
                        type: 'read'
                        properties: {}
                    }, Memory.readByteArray(this.buf, retval))
                    lastReadTimestamp = now
                  else
                    drop = stream.stats.drop
                    drop.buffers++
                    drop.bytes += retval
                  read = stream.stats.read
                  read.buffers++
                  read.bytes += retval
                  stream.dirty = true

        undefined


  return services
