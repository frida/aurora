"use strict";

const streams = [];
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
        field = fields[j];
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
let netLibrary = 'libSystem.B.dylib';
let connectImpl = Module.findExportByName(netLibrary, 'connect$UNIX2003');
if (connectImpl == null) {
  connectImpl = Module.findExportByName(netLibrary, 'connect');
}
if (connectImpl == null) {
  netLibrary = 'ws2_32.dll';
  connectImpl = Module.findExportByName(netLibrary, 'connect');
  isWindows = connectImpl != null;
}
if (connectImpl != null) {
  Interceptor.attach(connectImpl, {
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
          return send({
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
}
let readImpl = Module.findExportByName(netLibrary, 'read$UNIX2003');
if (readImpl == null) {
  readImpl = Module.findExportByName(netLibrary, 'read');
}
if (readImpl != null) {
  Interceptor.attach(readImpl, {
    onEnter: function (args) {
      this.fd = args[0].toInt32();
      return this.buf = args[1];
    },
    onLeave: function (retval) {
      if (retval.toInt32() > 0) {
        const stream = getStreamByFileDescriptor(this.fd);
        if (stream.status !== 'muted') {
          const now = Date.now();
          if ((lastReadTimestamp == null) || now - lastReadTimestamp >= 250) {
            send({
              type: 'stream:event',
              stream_id: stream.id,
              payload: {
                type: 'read',
                properties: {}
              }
            }, Memory.readByteArray(this.buf, retval));
            lastReadTimestamp = now;
          } else {
            const drop = stream.stats.drop;
            drop.buffers++;
            drop.bytes += retval;
          }
          const read = stream.stats.read;
          read.buffers++;
          read.bytes += retval;
          return stream.dirty = true;
        }
      }
    }
  });
}
