'use strict';

let pusherWs = null;
let socketId = null;
let authToken = null;
let apiBaseUrl = null;
let reverbWsUrl = null;
const APP_KEY = 'xtsedffitwzc6vpwl7tz';

const subscribedChannels = new Map();
let reconnectTimer = null;
let pingInterval = null;
let reconnectDelay = 3000;

function initUrls() {
  const host = self.location.hostname;
  apiBaseUrl = 'http://' + host + ':8000';
  reverbWsUrl = 'ws://' + host + ':8080/app/' + APP_KEY + '?protocol=7&client=sw&version=8.3.0';
  console.log('[SW] apiBaseUrl:', apiBaseUrl);
  console.log('[SW] reverbWsUrl:', reverbWsUrl);
}
initUrls();

function connectReverb() {
  if (pusherWs && (pusherWs.readyState === 0 || pusherWs.readyState === 1)) return;
  clearTimeout(reconnectTimer);
  clearInterval(pingInterval);
  console.log('[SW] Connexion Reverb...', reverbWsUrl);
  try {
    pusherWs = new WebSocket(reverbWsUrl);
  } catch (e) {
    console.warn('[SW] WS error:', e);
    scheduleReconnect();
    return;
  }
  pusherWs.onopen = function() {
    console.log('[SW] Reverb connecte');
    reconnectDelay = 3000;
    clearInterval(pingInterval);
    pingInterval = setInterval(function() {
      if (pusherWs && pusherWs.readyState === 1) {
        pusherWs.send(JSON.stringify({ event: 'pusher:ping', data: {} }));
      }
    }, 25000);
  };
  pusherWs.onmessage = function(event) {
    var msg;
    try { msg = JSON.parse(event.data); } catch(e) { return; }
    handlePusherMessage(msg);
  };
  pusherWs.onclose = function(event) {
    console.log('[SW] WS ferme code:', event.code);
    clearInterval(pingInterval);
    scheduleReconnect();
  };
  pusherWs.onerror = function() {
    clearInterval(pingInterval);
    scheduleReconnect();
  };
}

function scheduleReconnect() {
  if (!authToken) return;
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(function() {
    connectReverb();
    reconnectDelay = Math.min(reconnectDelay * 2, 30000);
  }, reconnectDelay);
}

function handlePusherMessage(msg) {
  if (msg.event === 'pusher:connection_established') {
    var data = JSON.parse(msg.data || '{}');
    socketId = data.socket_id;
    console.log('[SW] Socket ID:', socketId);
    resubscribeAll();
  } else if (msg.event === 'pusher:pong') {
    // keepalive
  } else if (msg.event === 'pusher_internal:subscription_succeeded') {
    console.log('[SW] Souscrit:', msg.channel);
  } else {
    var handlers = subscribedChannels.get(msg.channel);
    if (!handlers) return;
    var payload = {};
    try { payload = JSON.parse(msg.data || '{}'); } catch(e) {}
    var handler = handlers[msg.event];
    if (typeof handler === 'function') handler(payload);
  }
}

async function subscribePresenceChannel(channelName) {
  if (!socketId || !authToken || !apiBaseUrl) return;
  var formData = 'socket_id=' + encodeURIComponent(socketId) + '&channel_name=' + encodeURIComponent(channelName);
  try {
    var res = await fetch(apiBaseUrl + '/broadcasting/auth', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Bearer ' + authToken,
        'Accept': 'application/json',
      },
      body: formData,
    });
    if (!res.ok) throw new Error('Auth HTTP ' + res.status);
    var authData = await res.json();
    if (pusherWs && pusherWs.readyState === 1) {
      pusherWs.send(JSON.stringify({
        event: 'pusher:subscribe',
        data: {
          channel: channelName,
          auth: authData.auth,
          channel_data: authData.channel_data || '',
        },
      }));
      console.log('[SW] Subscribe envoye:', channelName);
    }
  } catch(e) {
    console.warn('[SW] Auth failed pour', channelName, ':', e.message);
  }
}

async function resubscribeAll() {
  for (var entry of subscribedChannels) {
    await subscribePresenceChannel(entry[0]);
    await new Promise(function(r) { setTimeout(r, 100); });
  }
}

self.addEventListener('message', async function(event) {
  if (!event.data) return;
  var type = event.data.type;

  if (type === 'SET_AUTH_TOKEN') {
    authToken = event.data.token;
    if (event.data.apiBaseUrl) apiBaseUrl = event.data.apiBaseUrl;
    if (event.data.reverbWsUrl) reverbWsUrl = event.data.reverbWsUrl;
    console.log('[SW] Token recu, connexion...');
    connectReverb();

  } else if (type === 'SUBSCRIBE_CONVERSATION') {
    var convId = event.data.conversationId;
    var channelName = 'presence-conversation.' + convId;
    if (!subscribedChannels.has(channelName)) {
      subscribedChannels.set(channelName, {
        'call.initiated': handleCallInitiated,
        'message.sent': handleMessageSent,
        'call.status': handleCallStatus,
      });
    }
    if (socketId && pusherWs && pusherWs.readyState === 1) {
      await subscribePresenceChannel(channelName);
    }

  } else if (type === 'SUBSCRIBE_USER') {
    var userId = event.data.userId;
    var uChannelName = 'presence-user.' + userId;
    if (!subscribedChannels.has(uChannelName)) {
      subscribedChannels.set(uChannelName, {
        'notification.new': handleNotification,
      });
    }
    if (socketId && pusherWs && pusherWs.readyState === 1) {
      await subscribePresenceChannel(uChannelName);
    }

  } else if (type === 'CANCEL_CALL_NOTIFICATION') {
    self.registration.getNotifications({ tag: 'call-' + event.data.callId })
      .then(function(notifs) { notifs.forEach(function(n) { n.close(); }); });

  } else if (type === 'DISCONNECT') {
    clearInterval(pingInterval);
    clearTimeout(reconnectTimer);
    if (pusherWs) { pusherWs.close(); pusherWs = null; }
    subscribedChannels.clear();
    authToken = null;
  }
});

function handleCallInitiated(payload) {
  var callerName = (payload.caller && payload.caller.full_name) ? payload.caller.full_name : 'Appel entrant';
  var callType = payload.type || 'audio';
  var callId = payload.call_id || payload.id;
  var convId = payload.conversation_id;
  var emoji = callType === 'video' ? 'Video' : 'Audio';

  console.log('[SW] call.initiated:', callerName, callType);

  self.registration.showNotification(callerName, {
    body: emoji + ' - Appel ' + callType + ' entrant...',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: 'call-' + callId,
    requireInteraction: true,
    renotify: true,
    vibrate: [500, 200, 500, 200, 500],
    actions: [
      { action: 'reject', title: 'Refuser' },
      { action: 'answer', title: 'Repondre' },
    ],
    data: { callId: callId, conversationId: convId, callType: callType, callerName: callerName },
  }).catch(function(e) { console.warn('[SW] showNotification error:', e); });

  self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then(function(clients) {
      clients.forEach(function(c) { c.postMessage({ type: 'INCOMING_CALL', payload: payload }); });
    });
}

function handleMessageSent(payload) {
  var senderName = (payload.sender && payload.sender.full_name) ? payload.sender.full_name : 'Nouveau message';
  var body = payload.type === 'text' ? (payload.body || '') : 'Fichier ' + payload.type;
  var convId = payload.conversation_id;

  self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then(function(clients) {
      var hasFocused = clients.some(function(c) { return c.focused; });
      if (!hasFocused) {
        self.registration.showNotification(senderName, {
          body: body,
          icon: '/icons/Icon-192.png',
          tag: 'msg-' + convId + '-' + Date.now(),
          data: { conversationId: convId },
        }).catch(function(e) { console.warn('[SW] msg notif error:', e); });
      }
      clients.forEach(function(c) { c.postMessage({ type: 'NEW_MESSAGE', payload: payload }); });
    });
}

function handleCallStatus(payload) {
  console.log('[SW] call.status:', payload.status);
  if (['ended', 'rejected', 'missed'].indexOf(payload.status) !== -1) {
    if (payload.call_id) {
      self.registration.getNotifications({ tag: 'call-' + payload.call_id })
        .then(function(notifs) { notifs.forEach(function(n) { n.close(); }); });
    }
  }
  self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then(function(clients) {
      clients.forEach(function(c) { c.postMessage({ type: 'CALL_STATUS', payload: payload }); });
    });
}

function handleNotification(payload) {
  console.log('[SW] notification.new:', payload.type);
  self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then(function(clients) {
      clients.forEach(function(c) { c.postMessage({ type: 'NOTIFICATION_NEW', payload: payload }); });
    });
}

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var data = event.notification.data || {};
  var urlPath = '/';

  if (event.action === 'answer') {
    urlPath = '/#/conversations/' + data.conversationId + '?incomingCall=' + data.callId;
  } else if (event.action === 'reject') {
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function(clients) {
        clients.forEach(function(c) { c.postMessage({ type: 'REJECT_CALL', callId: data.callId }); });
      });
    return;
  } else if (data.conversationId) {
    urlPath = '/#/conversations/' + data.conversationId;
  }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function(clients) {
        for (var i = 0; i < clients.length; i++) {
          if ('focus' in clients[i]) {
            clients[i].focus();
            clients[i].postMessage({ type: 'NAVIGATE', url: urlPath, data: data });
            return;
          }
        }
        return self.clients.openWindow(urlPath);
      })
  );
});

self.addEventListener('install', function() {
  console.log('[SW] Installe');
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  console.log('[SW] Active');
  event.waitUntil(self.clients.claim());
});
