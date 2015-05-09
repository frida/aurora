const app = require("express")();
const frida = require("frida");
const http = require("http").Server(app);
const io = require("socket.io")(http);

const deviceManager = frida.getDeviceManager();
const handlers = {};
var current = null;
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
      getDeviceById(payload.device)
      .then(function (device) {
        return device.attach(payload.pid);
      })
      .then(function (session) {
        current.session = session;
        return session.createScript(payload.source, {
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
        current.session.events.listen('detached', function () {
          if (current !== null && current.device === payload.device && current.pid === payload.pid) {
            current = null;
          }
          io.emit('+detached', {});
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
    if (current !== null) {
      current.script.postMessage(message)
      .then(resolve)
      .catch(reject);
    } else {
      reject(new Error("Not attached"));
    }
  });
};

function onMessage(message, data) {
  console.log("MESSAGE!", message, data);
  io.emit('+message', {
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
