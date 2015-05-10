"use strict";

const streams = [];
const knownPeers = {};
let lastStreamId = 1;
let lastReadTimestamp = null;

function createStream(fd) {
  const stream = {
    id: lastStreamId++,
    status: 'normal',
    fd: fd,
    type: Socket.type(fd) || 'file',
    localAddress: Socket.localAddress(fd),
    peerAddress: Socket.peerAddress(fd),
    stats: {
      read: {
        buffers: 0,
        bytes: 0
      },
      write: {
        buffers: 0,
        bytes: 0
      },
      drop: {
        buffers: 0,
        bytes: 0
      }
    },
    dirty: false
  };
  streams.push(stream);
  return stream;
}

function findStreamById(id) {
  for (let i = 0, len = streams.length; i !== len; i++) {
    const stream = streams[i];
    if (stream.id === id)
      return stream;
  }
  return null;
}

function getStreamByFileDescriptor(fd) {
  for (let i = 0, len = streams.length; i !== len; i++) {
    const stream = streams[i];
    if (stream.fd === fd) {
      return stream;
    }
  }
  const stream = createStream(fd);
  send({
    type: 'streams:add',
    payload: {
      id: stream.id,
      status: stream.status,
      fd: stream.fd,
      type: stream.type,
      localAddress: stream.localAddress,
      peerAddress: stream.peerAddress,
      stats: stream.stats
    }
  });
  return stream;
}

function updateStream(id, updates) {
  const stream = findStreamById(id);
  if (stream !== null) {
    for (const k in updates) {
      const v = updates[k];
      stream[k] = v;
    }
    const allUpdates = {};
    allUpdates[id] = updates;
    send({
      type: 'streams:update',
      payload: allUpdates
    });
  }
};

function receiveMute() {
  recv('stream:mute', function (message) {
    updateStream(message.stream_id, {
      status: 'muted'
    });
    receiveMute();
  });
};
receiveMute();

function receivePull() {
  recv('streams:pull', function (message) {
    const fields = message.payload;
    const updates = {};
    for (let i = 0, len = streams.length; i !== len; i++) {
      const stream = streams[i];
      if (stream.status === 'muted' || !stream.dirty) {
        continue;
      }
      stream.dirty = false;
      const u = {};
      for (let j = 0, len1 = fields.length; j !== len1; j++) {
        const field = fields[j];
        u[field] = stream[field];
      }
      updates[stream.id] = u;
    }
    send({
      type: 'streams:update',
      payload: updates
    });
    receivePull();
  });
};
receivePull();

const AF_INET = 2;
let isWindows = false;
let netLibrary;

let connectImpls = [];
switch (Process.platform) {
  case 'darwin':
    netLibrary = "libSystem.B.dylib";
    connectImpls.push(Module.findExportByName(netLibrary, "connect$UNIX2003"));
    connectImpls.push(Module.findExportByName(netLibrary, "connect"));
    break;
  case 'windows':
    isWindows = true;
    netLibrary = "ws2_32.dll";
    connectImpls.push(Module.findExportByName(netLibrary, "connect"));
    break;
}
connectImpls
.filter(function (impl) { return impl !== null; })
.forEach(function (impl) {
  Interceptor.attach(impl, {
    onEnter: function (args) {
      const sockAddr = args[1];
      let family;
      if (isWindows) {
        family = Memory.readU8(sockAddr);
      } else {
        family = Memory.readU8(sockAddr.add(1));
      }
      if (family === AF_INET) {
        const fd = args[0].toInt32();
        const stream = getStreamByFileDescriptor(fd);
        if (stream.status !== 'muted') {
          const ip = Memory.readU8(sockAddr.add(4)) + "." + Memory.readU8(sockAddr.add(5)) + "." + Memory.readU8(sockAddr.add(6)) + "." + Memory.readU8(sockAddr.add(7));
          const port = (Memory.readU8(sockAddr.add(2)) << 8) | Memory.readU8(sockAddr.add(3));
          updateStream(stream.id, {
            peerAddress: {
              ip: ip,
              port: port
            }
          });
          knownPeers[ip + ":" + port] = true;
          send({
            type: 'stream:event',
            stream_id: stream.id,
            payload: {
              type: 'connect',
              properties: {
                ip: ip,
                port: port
              }
            }
          });
        }
      }
    }
  });
});

let readImpls = [];
readImpls.push(Module.findExportByName(netLibrary, 'read$UNIX2003'));
readImpls.push(Module.findExportByName(netLibrary, 'read'));
readImpls
.filter(function (impl) { return impl !== null; })
.forEach(function (impl) {
  Interceptor.attach(impl, {
    onEnter: function (args) {
      this.fd = args[0].toInt32();
      this.buf = args[1];
    },
    onLeave: function (retval) {
      var numBytesRead = retval.toInt32();
      if (numBytesRead > 0) {
        const stream = getStreamByFileDescriptor(this.fd);
        if (stream.status !== 'muted') {
          const now = Date.now();
          if ((lastReadTimestamp === null) || now - lastReadTimestamp >= 250) {
            const peerAddr = Socket.peerAddress(this.fd);
            if (peerAddr !== null) {
              const ip = peerAddr.ip;
              const port = peerAddr.port;
              const peerKey = ip + ":" + port;
              if (knownPeers[peerKey] === undefined) {
                updateStream(stream.id, {
                  peerAddress: {
                    ip: ip,
                    port: port
                  }
                });
                send({
                  type: 'stream:event',
                  stream_id: stream.id,
                  payload: {
                    type: 'connect',
                    properties: {
                      ip: ip,
                      port: port
                    }
                  }
                });
                knownPeers[peerKey] = true;
              }
            }
            send({
              type: 'stream:event',
              stream_id: stream.id,
              payload: {
                type: 'read',
                properties: {}
              }
            }, Memory.readByteArray(this.buf, numBytesRead));
            lastReadTimestamp = now;
          } else {
            const drop = stream.stats.drop;
            drop.buffers++;
            drop.bytes += numBytesRead;
          }
          const read = stream.stats.read;
          read.buffers++;
          read.bytes += numBytesRead;
          stream.dirty = true;
        }
      }
    }
  });
});
