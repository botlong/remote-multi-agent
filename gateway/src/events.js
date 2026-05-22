'use strict';

const REPLAY_BUFFER_SIZE = 200;

class EventBus {
  constructor() {
    this.subscribers = new Map();
    // Per-session ring buffer of the last N events, so clients that reconnect
    // (e.g. after the gateway restarted or a brief network drop) can catch
    // up on anything emitted while they were disconnected.
    this.replay = new Map();
    this._nextEventId = 1;
  }

  subscribe(sessionId, response, lastEventId) {
    let set = this.subscribers.get(sessionId);
    if (!set) {
      set = new Set();
      this.subscribers.set(sessionId, set);
    }
    set.add(response);
    response.write(': connected\n\n');

    // Replay buffered events for this session so the new subscriber sees
    // everything that happened before it connected.
    const buffered = this.replay.get(sessionId);
    if (buffered && buffered.length > 0) {
      const startAfter = lastEventId ? parseInt(lastEventId, 10) : 0;
      for (const event of buffered) {
        // If client sent Last-Event-ID, only replay events after that ID
        if (startAfter && event._eventId && event._eventId <= startAfter) continue;
        const id = event._eventId || '';
        response.write(`id: ${id}\nevent: gateway\ndata: ${JSON.stringify(event)}\n\n`);
      }
    }

    return () => {
      set.delete(response);
      if (set.size === 0) this.subscribers.delete(sessionId);
    };
  }

  emit(event) {
    // Assign a monotonic event ID for Last-Event-ID reconnect support
    event._eventId = this._nextEventId++;

    // Delta events are incremental — replaying them after reconnect would
    // duplicate text (the client already fetches full messages via REST).
    const skipReplay = event.type === 'message.delta' ||
      event.type === 'message.part.delta' ||
      event.type === 'command.updated';
    if (!skipReplay) {
      let buf = this.replay.get(event.sessionId);
      if (!buf) {
        buf = [];
        this.replay.set(event.sessionId, buf);
      }
      buf.push(event);
      if (buf.length > REPLAY_BUFFER_SIZE) buf.splice(0, buf.length - REPLAY_BUFFER_SIZE);
    }

    const subscribers = this.subscribers.get(event.sessionId);
    if (!subscribers || subscribers.size === 0) return;
    const payload = `id: ${event._eventId}\nevent: gateway\ndata: ${JSON.stringify(event)}\n\n`;
    for (const response of subscribers) {
      response.write(payload);
    }
  }

  clearSession(sessionId) {
    this.replay.delete(sessionId);
  }
}

function makeEvent({ type, sessionId, agentId, data = {}, raw = {} }) {
  return {
    type,
    sessionId,
    agentId,
    timestamp: Date.now(),
    data,
    raw,
  };
}

module.exports = {
  EventBus,
  makeEvent,
};
