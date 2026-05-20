'use strict';

const REPLAY_BUFFER_SIZE = 200;

class EventBus {
  constructor() {
    this.subscribers = new Map();
    // Per-session ring buffer of the last N events, so clients that reconnect
    // (e.g. after the gateway restarted or a brief network drop) can catch
    // up on anything emitted while they were disconnected.
    this.replay = new Map();
  }

  subscribe(sessionId, response) {
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
      for (const event of buffered) {
        response.write(`event: gateway\ndata: ${JSON.stringify(event)}\n\n`);
      }
    }

    return () => {
      set.delete(response);
      if (set.size === 0) this.subscribers.delete(sessionId);
    };
  }

  emit(event) {
    // Always append to the replay buffer, even if there are no current
    // subscribers — that way a client that connects later still sees it.
    let buf = this.replay.get(event.sessionId);
    if (!buf) {
      buf = [];
      this.replay.set(event.sessionId, buf);
    }
    buf.push(event);
    if (buf.length > REPLAY_BUFFER_SIZE) buf.splice(0, buf.length - REPLAY_BUFFER_SIZE);

    const subscribers = this.subscribers.get(event.sessionId);
    if (!subscribers || subscribers.size === 0) return;
    const payload = `event: gateway\ndata: ${JSON.stringify(event)}\n\n`;
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
