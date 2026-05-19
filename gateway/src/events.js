'use strict';

class EventBus {
  constructor() {
    this.subscribers = new Map();
  }

  subscribe(sessionId, response) {
    let set = this.subscribers.get(sessionId);
    if (!set) {
      set = new Set();
      this.subscribers.set(sessionId, set);
    }
    set.add(response);
    response.write(': connected\n\n');
    return () => {
      set.delete(response);
      if (set.size === 0) this.subscribers.delete(sessionId);
    };
  }

  emit(event) {
    const subscribers = this.subscribers.get(event.sessionId);
    if (!subscribers || subscribers.size === 0) return;
    const payload = `event: gateway\ndata: ${JSON.stringify(event)}\n\n`;
    for (const response of subscribers) {
      response.write(payload);
    }
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
