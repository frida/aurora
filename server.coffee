connect = require('connect')
cors = require('connect-xcors')
express = require('express')
geoip = require('geoip-lite')

class Server
  run: ->
    corsOptions =
      origins: []
      methods: ['HEAD', 'GET']
      resources: [
        { pattern: "/" }
      ]
    @_app = express()
    @_app.use(connect.logger({ format: 'dev' }))
    @_app.use(cors(corsOptions))
    @_app.get "/geoip/json/:ip", (req, res) ->
      geo = geoip.lookup(req.params.ip)
      if (ll = geo?.ll)?
        res.send({
          latitude: ll[0]
          longitude: ll[1]
        })
      else
        res.statusCode = 404
        res.send("Not Found")
    @_app.listen(8008)

server = new Server()
server.run()
