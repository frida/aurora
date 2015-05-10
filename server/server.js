const app = require("express")();
const frida = require("frida");
const fs = require("fs");
const geoip = require("geoip-lite");
const http = require("http").Server(app);
const io = require("socket.io")(http);
const path = require("path");

const deviceManager = frida.getDeviceManager();
const handlers = {};
var current = null;

deviceManager.events.listen('changed', onDevicesChanged);

handlers['.enumerate-devices'] = function () {
  return deviceManager.enumerateDevices();
};
handlers['.enumerate-processes'] = function (payload) {
  return getDeviceById(payload.device.id)
  .then(function (device) {
    return device.enumerateProcesses();
  })
  .then(function (processes) {
    return processes.map(processToJson);
  });
};
handlers['.attach'] = function (payload) {
  return new Promise(function (resolve, reject) {
    if (current === null) {
      current = {};
      fs.readFile(path.join(__dirname, "script.js"), {
        encoding: 'utf-8',
      }, function (err, source) {
        if (err) {
          reject(err);
          return;
        }

        getDeviceById(payload.device)
        .then(function (device) {
          return device.attach(payload.pid);
        })
        .then(function (session) {
          current.session = session;
          return session.createScript(source, {
            name: "aurora"
          });
        })
        .then(function (script) {
          current.script = script;
          script.events.listen('message', onMessage);
          return script.load();
        })
        .then(function () {
          current.device = payload.device;
          current.pid = payload.pid;
          io.emit('attached', {
            device: payload.device,
            pid: payload.pid
          });
          current.session.events.listen('detached', function () {
            if (current !== null && current.device === payload.device && current.pid === payload.pid) {
              current = null;
            }
            io.emit('detached', {
              device: payload.device,
              pid: payload.pid
            });
          });
          resolve();
        })
        .catch(function (error) {
          if (current.script !== undefined)
            current.script.events.unlisten('message', onMessage);
          if (current.session !== undefined)
            current.session.detach();
          current = null;
          reject(error);
        });
      });
    } else {
      reject(new Error("Already attached"));
    }
  });
};
handlers['.detach'] = function (payload) {
  return new Promise(function (resolve, reject) {
    if (current !== null && payload.device === current.device && payload.pid === current.pid) {
      current.script.unload();
      current.session.detach();
      current = null;
      resolve();
    } else {
      reject(new Error("Not attached"));
    }
  });
};
handlers['.post-message'] = function (message) {
  return new Promise(function (resolve, reject) {
    if (current !== null && current.script !== undefined) {
      current.script.postMessage(message)
      .then(resolve)
      .catch(reject);
    } else {
      reject(new Error("Not attached"));
    }
  });
};
handlers['.lookup-ip'] = function (payload) {
  return new Promise(function (resolve, reject) {
    const geo = geoip.lookup(payload.ip);
    const ll = (geo || {}).ll;
    if (ll !== undefined) {
      resolve({
        latitude: ll[0],
        longitude: ll[1]
      });
    } else {
      reject(new Error("Not found"));
    }
  });
};

function onDevicesChanged() {
  io.emit('devices-changed', {});
}

function onMessage(message, data) {
  io.emit('message', {
    device: current.device,
    pid: current.pid,
    message: message,
    data: data
  });
}

function getDeviceById(id) {
  return deviceManager.enumerateDevices()
  .then(function (devices) {
    const matching = devices.filter(function (device) { return device.id === id; });
    if (matching.length === 0)
      throw new Error("No such device");
    return matching[0];
  });
}

app.get("/", function (req, res) {
  res.sendfile("index.html");
});

io.on("connection", function (socket) {
  if (current !== null && current.device !== undefined && current.pid !== undefined) {
    io.emit('attached', {
      device: current.device,
      pid: current.pid
    });
  }
  socket.on('stanza', function (stanza) {
    const handler = handlers[stanza.name];
    if (handler !== undefined) {
      handler(stanza.payload)
      .then(function (result) {
        socket.emit('stanza', {
          id: stanza.id,
          name: '+result',
          payload: result
        });
      })
      .catch(function (error) {
        console.log(stanza.name, "failed:", error);
        socket.emit('stanza', {
          id: stanza.id,
          name: '+error',
          payload: error.stack
        });
      });
    } else {
      console.log(stanza.name, "is unhandled");
      socket.emit('stanza', {
        id: stanza.id,
        name: '+error',
        payload: "Unsupported request"
      });
    }
  });
});

http.listen(3000, function () {
  console.log("listening on *:3000");
});

function processToJson(process) {
  return {
    pid: process.pid,
    name: process.name,
    smallIcon: iconToJson(process.smallIcon),
    largeIcon: iconToJson(process.largeIcon)
  };
}

function iconToJson(icon) {
  if (icon === null)
    return null;

  return {
    width: icon.width,
    height: icon.height,
    rowstride: icon.rowstride,
    pixels: icon.pixels.toString('base64')
  };
}
