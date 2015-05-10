define ["jquery", "beam/main", "./services", "three", "globe", "lcss!css/app", "jquery.dd"], ($, beam, services, three, DAT) ->
  exports = {}


  class exports.View extends beam.views.View
    initialize: (@element) ->
      @processSelector = =>
        view = new ProcessSelector(this)
        @element.append(view.element)
        view
      @progressIndicator = =>
        view = new ProgressIndicator(this)
        @element.append(view.element)
        view

    class ProcessSelector extends beam.views.View
      initialize: ->
        @element = @_loadPartial('process-selector')
        @devices = @element.find("[data-view='devices']")
        @processes = @element.find("[data-view='processes']")

      getSelectedDevice: ->
        parseInt(@devices.children().filter(":selected").attr('value'))

      getSelectedPid: ->
        parseInt(@processes.children().filter(":selected").attr('value'))

      onSelectedDeviceChanged: (handler) ->
        @devices.change(handler)

      onSelect: (handler) ->
        @element.find("[data-action='attach']").click =>
          try
            handler(@getSelectedDevice(), @getSelectedPid())
          catch e
            console.log(e.message)
            console.log(e.stack)
          false

      setDevices: (devices) ->
        @devices.children().remove()
        devices = devices.slice(0)
        devices.forEach (device) =>
          entry = $("<option></option>")
          entry.attr('value', device.id)
          entry.text(device.name)
          @devices.append(entry)
        @devices.msDropDown()

      setProcesses: (processes) ->
        @processes.children().remove()
        processes = processes.slice(0)
        processes.sort (a, b) ->
          aHasIcon = a.smallIcon?
          bHasIcon = b.smallIcon?
          if aHasIcon == bHasIcon
            a.name.toLowerCase().localeCompare(b.name.toLowerCase())
          else if aHasIcon
            -1
          else
            1
        processes.forEach (process) =>
          entry = $("<option></option>")
          entry.attr('value', process.pid)
          if (icon = process.smallIcon)?
            entry.attr("data-width", icon.width)
            entry.attr("data-height", icon.height)
            entry.attr("data-pixels", icon.pixels)
          entry.text(process.name)
          @processes.append(entry)
        @processes.msDropDown()

    class ProgressIndicator extends beam.views.View
      initialize: ->
        @element = @_loadPartial('progress-indicator')

        @streams = new Streams(this, @element.find("[data-view='streams']"))
        @preview = new Preview(this, @element.find("[data-view='preview']"))
        @globe = new Globe(this, @element.find("[data-view='globe']"))

        @_cancel = @element.find("[data-action='cancel']")

      update: (details) ->
        message = switch details.state
          when 'attaching'
            "Attaching to pid #{details.pid}..."
          when 'attached'
            "Attached to pid #{details.pid}. Waiting for data..."
          when 'failed'
            "Failed to attach to pid #{details.pid}: #{details.error}"
          when 'closed'
            "Detached from pid #{details.pid}"
        @setText('message', message)

      onCancel: (handler) ->
        @_cancel.click ->
          handler()

      class Streams extends beam.views.Collection
        initialize: (wrapper) ->
          super(wrapper.find("[data-view='content']"), Stream)

        class Stream extends beam.views.View
          initialize: ->
            @element = @_loadPartial('capture-stream')

          onMute: (handler) ->
            @element.find("[data-action='mute']").click ->
              handler()

      class Preview extends beam.views.View
        initialize: (@element) ->
          @_itemTemplate = @_loadPartial("preview-item")

        add: (item) ->
          children = @element.children()
          if children.length == 3
            children.first().remove()
          view = @_itemTemplate.clone()
          view.attr('data-stream', item.stream.get('id'))
          view.find("[data-bind='summary']").text("Stream #{item.stream.get('id')}: #{item.summary}")
          if item.data?
            data = new Uint8Array(item.data)
            if data.length > 0
              view.find("[data-bind='hex-data']").text(@_hexify(data))
              view.find("[data-bind='ascii-data']").text(@_asciify(data))
          @element.append(view)

        remove: (streamId) ->
          @element.find("[data-stream='#{streamId}']").remove()

        _hexify: (data, limit = 48) ->
          result = ""
          lineOffset = 0
          lastIndex = Math.min(data.length, limit) - 1
          for i in [0..lastIndex]
            value = data[i]
            if lineOffset > 0
              result += " "
            if lineOffset % 8 == 0
              result += " "
            c = value.toString(16).toUpperCase()
            if c.length == 1
              result += "0"
            result += c
            if lineOffset == 15 or i == lastIndex
              lineOffset = 0
            else
              lineOffset++
          result

        _asciify: (data, limit = 48) ->
          result = ""
          lineOffset = 0
          lastIndex = Math.min(data.length, limit) - 1
          for i in [0..lastIndex]
            value = data[i]
            if value >= 32 and value <= 126
              result += String.fromCharCode(value)
            else
              result += "."
            if lineOffset == 15 or i == lastIndex
              result += " "
              lineOffset = 0
            else
              lineOffset++
          result

      class Globe extends beam.views.View
        initialize: (@element) ->
          @_datapoints = []
          @_animating = true
          window.requestAnimationFrame =>
            @globe = new DAT.Globe(@element.get(0))
            @globe.animate()
            @_animate()
          downTimestamp = null
          wasAnimating = null
          @element.mousedown (e) =>
            downTimestamp = e.timeStamp
            wasAnimating = @_animating
            @_animating = false
          @element.click (e) =>
            if e.timeStamp - downTimestamp < 300
              @_animating = not wasAnimating
            else
              @_animating = wasAnimating

        _animate: =>
          if @_animating
            @globe.rotateBy(0.001, 0.001)
          window.requestAnimationFrame(@_animate)

        addConnectDataPoint: (ip, port, latitude, longitude) ->
          @_datapoints.push(latitude, longitude, (0.25 + (port / 65535) * 0.75) * 0.3)
          @globe.clearData()
          @globe.addData(@_datapoints, {
            format: 'magnitude'
            name: "connect()"
            animated: true
          })
          @globe.createPoints()
          @globe.time = 0.0
          @globe.animateTo(latitude, longitude, true)


  class exports.Presenter extends beam.presenters.Presenter
    initialize: ->
      @reset()
      @services.frida.capture.on('closed', @_onClosed)

    dispose: ->
      super
      @services.frida.capture.off('closed', @_onClosed)

    reset: ->
      @processSelector = new ProcessSelector(this, @view.processSelector(), @services)
      @processSelector.onSelect(@_onSelect)
      @processSelector.onAttach(@_onAttach)
      @progress = null

    _onSelect: (device, pid) =>
      @processSelector.dispose()
      @processSelector = null
      @progress = new ProgressIndicator(this, @view.progressIndicator(), @services)
      @progress.update({
        state: 'attaching'
        pid: pid
      })

      request = @services.frida.capture.open(device, pid)
      request.done =>
        @progress.update({
          state: 'attached'
          pid: pid
        })
        @progress.onCancel =>
          @services.frida.capture.close(device, pid).always =>
            @progress.dispose()
            @progress = null
            @reset()
      request.fail (error) =>
        @progress.update({
          state: 'failed'
          error: error
        })

    _onAttach: (device, pid) =>
      @processSelector.dispose()
      @processSelector = null

      @progress = new ProgressIndicator(this, @view.progressIndicator(), @services)
      @progress.update({
        state: 'attached'
        pid: pid
      })
      @progress.onCancel =>
        @services.frida.capture.close(device, pid).always =>
          @progress.dispose()
          @progress = null
          @reset()

    _onClosed: (device, pid) =>
      @progress?.update({
        state: 'closed'
        pid: pid
      })

    class ProcessSelector extends beam.presenters.Presenter
      initialize: ->
        @view.onSelectedDeviceChanged(@_refreshProcesses)

        @_onAttach = null
        @services.frida.on('attached', @_onAttached)
        @services.frida.on('devices-changed', @_refreshDevices)
        @_refreshDevices()

      dispose: ->
        @services.frida.off('devices-changed', @_refreshDevices)
        @services.frida.off('attached', @_onAttached)
        super

      _refreshDevices: =>
        @view.setDevices([])
        @services.frida.enumerateDevices().done (devices) =>
          @view.setDevices(devices)
          @_refreshProcesses()

      _refreshProcesses: =>
        @view.setProcesses([])
        request = @services.frida.enumerateProcesses(@view.getSelectedDevice())
        request.done (processes) =>
          @view.setProcesses(processes)
        request.fail (error) ->
          console.log(error)

      _onAttached: (payload) =>
        @_onAttach(payload.device, payload.pid)

      onSelect: (handler) ->
        @view.onSelect(handler)

      onAttach: (handler) ->
        @_onAttach = handler

    class ProgressIndicator extends beam.presenters.Presenter
      initialize: ->
        @streams = new Streams(this, @view.streams, @services)
        @preview = new Preview(this, @view.preview, @services)
        @globe = new Globe(this, @view.globe, @services)
        @_onCancel = null
        @view.onCancel =>
          @_onCancel?()

      update: (details) ->
        @view.update(details)

      onCancel: (handler) ->
        @_onCancel = handler

      class Streams extends beam.presenters.Collection
        initialize: ->
          super(Stream)
          for stream in @services.frida.capture.streams
            @add([stream])
          @services.frida.capture.on('added', @_onAdded)
          @services.frida.capture.on('updated', @_onUpdated)
          @_pullTimer = window.setInterval(@_pullStats, 1000)

        dispose: ->
          super
          @services.frida.capture.off('added', @_onAdded)
          @services.frida.capture.off('updated', @_onUpdated)
          window.clearInterval(@_pullTimer)

        _onAdded: (stream) =>
          @add([stream])

        _onUpdated: (stream, updates) =>
          if (status = updates.status)?
            id = stream.get('id')
            if status == 'muted'
              @removeMatching (presenter) ->
                presenter.stream.get('id') == id
            else
              existing = @find (presenter) ->
                presenter.stream.get('id') == id
              if not existing?
                @add([stream])

        _pullStats: =>
          @services.frida.capture.pull(['stats'])

        class Stream extends beam.presenters.Presenter
          initialize: (@stream) ->
            @view.setText('id', @stream.get('id'))
            @view.setText('fd', @stream.get('fd'))
            @stream.on('updated', @_onUpdated)()
            @view.onMute(@_onMute)

          dispose: ->
            super
            @stream.off('updated', @_onUpdated)

          _onUpdated: =>
            type = @stream.get('type')
            @view.setText('type', type)
            if type != 'unix'
              address = @stream.get('peerAddress')
              @view.setText('peer', if address? then "#{address.ip}:#{address.port}" else "N/A")
            else
              @view.setText('peer', "N/A")
            stats = @stream.get('stats')
            @view.setText('bytes', stats.read.bytes + stats.write.bytes)
            @view.setText('dropped', stats.drop.bytes)

          _onMute: =>
            @stream.mute()

      class Preview extends beam.presenters.Presenter
        initialize: ->
          @services.frida.capture.on('updated', @_onUpdated)
          @services.bus.on('stream:appended', @_onAppended)

        dispose: ->
          super
          @services.frida.capture.off('updated', @_onUpdated)
          @services.bus.off('stream:appended', @_onAppended)

        _onUpdated: (stream, updates) =>
          if updates.status == 'muted'
            @view.remove(stream.get('id'))

        _onAppended: (message, sender) =>
          event = message.event
          keys = (k for own k, v of event.properties)
          keys.sort()
          pairs = ("#{k}=#{event.properties[k]}" for k in keys)
          @view.add({
            stream: message.stream
            summary: "#{event.type}(#{pairs.join(", ")})"
            data: event.data
          })

      class Globe extends beam.presenters.Presenter
        initialize: ->
          @services.bus.on('stream:appended', @_onAppended)

        dispose: ->
          super
          @services.bus.off('stream:appended', @_onAppended)

        _onAppended: (message, sender) =>
          if message.event.type == 'connect'
            properties = message.event.properties
            @services.frida.geoip.lookup(properties.ip).done (geo) =>
              @view.addConnectDataPoint(properties.ip, properties.port, geo.latitude, geo.longitude)


  return exports
