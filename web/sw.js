let pusherWs = null;
let socketId = null;
let authToken = null;
let subscribedChannels = new Map(); // channelName -> handlers
let reconnectTimer = null;
let pingInterval = null;
const SERVER_HOST = self.location.hostname; // même host que la page
const REVERB_PORT = 80; // avec nginx devant (voir problème #2)
const APP_KEY = 'xtsedffitwzc6vpwl7tz';

function connectReverb() {
  if (pusherWs && pusherWs.readyState === WebSocket.OPEN) return;
  
  clearTimeout(reconnectTimer);
  clearInterval(pingInterval);
  
  const url = `ws://${SERVER_HOST}:${REVERB_PORT}/app/${APP_KEY}?protocol=7&client=js&version=8.3.0`;
  
  try {
    pusherWs = new WebSocket(url);
  } catch(e) {
    console.warn('[SW] WS connect error:', e);
    scheduleReconnect();
    return;
  }
  
  pusherWs.onopen = () => {
    console.log('[SW] Reverb connecté');
    // Ping toutes les 30s pour garder la connexion vivante
    pingInterval = setInterval(() => {
      if (pusherWs && pusherWs.readyState === WebSocket.OPEN) {
        pusherWs.send(JSON.stringify({ event: 'pusher:ping', data: {} }));
      }
    }, 30000);
  };
  
  pusherWs.onmessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch(e) { return; }
    handlePusherMessage(msg);
  };
  
  pusherWs.onclose = scheduleReconnect;
  pusherWs.onerror = scheduleReconnect;
}

function scheduleReconnect() {
  clearInterval(pingInterval);
  reconnectTimer = setTimeout(connectReverb, 5000);
}

function handlePusherMessage(msg) {
  switch(msg.event) {
    case 'pusher:connection_established':
      const data = JSON.parse(msg.data || '{}');
      socketId = data.socket_id;
      // Re-souscrire tous les canaux sauvegardés
      resubscribeAll();
      break;
    
    case 'pusher:pong':
      break; // keepalive OK
    
    case 'pusher_internal:subscription_succeeded':
      console.log('[SW] Souscrit:', msg.channel);
      break;
    
    default:
      // Dispatcher l'event aux handlers enregistrés
      const handlers = subscribedChannels.get(msg.channel);
      if (handlers && handlers[msg.event]) {
        const payload = (() => {
          try { return JSON.parse(msg.data || '{}'); } catch(e) { return {}; }
        })();
        handlers[msg.event](payload);
      }
      break;
  }
}

async function subscribePresenceChannel(channelName) {
  if (!socketId || !authToken) return;
  
  // Auth auprès de Laravel Reverb
  const formData = `socket_id=${encodeURIComponent(socketId)}&channel_name=${encodeURIComponent(channelName)}`;
  
  try {
    const res = await fetch(`http://${SERVER_HOST}:8000/broadcasting/auth`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': `Bearer ${authToken}`,
        'Accept': 'application/json',
      },
      body: formData,
    });
    
    if (!res.ok) throw new Error(`Auth failed: ${res.status}`);
    const authData = await res.json();
    
    pusherWs.send(JSON.stringify({
      event: 'pusher:subscribe',
      data: {
        channel: channelName,
        auth: authData.auth,
        channel_data: authData.channel_data,
      },
    }));
  } catch(e) {
    console.warn('[SW] Subscribe auth failed:', e);
  }
}

function resubscribeAll() {
  for (const [channelName] of subscribedChannels) {
    subscribePresenceChannel(channelName);
  }
}

// Recevoir messages depuis Flutter Web
self.addEventListener('message', async (event) => {
  if (!event.data) return;
  
  switch(event.data.type) {
    case 'SET_AUTH_TOKEN':
      authToken = event.data.token;
      connectReverb();
      break;
    
    case 'SUBSCRIBE_CONVERSATION':
      const { conversationId } = event.data;
      const channelName = `presence-conversation.${conversationId}`;
      if (!subscribedChannels.has(channelName)) {
        subscribedChannels.set(channelName, {
          'call.initiated': handleCallInitiated,
          'message.sent': handleMessageSent,
          'call.status': handleCallStatus,
        });
      }
      if (socketId) await subscribePresenceChannel(channelName);
      break;
    
    case 'CANCEL_CALL_NOTIFICATION':
      self.registration.getNotifications({ tag: `call-${event.data.callId}` })
        .then(notifs => notifs.forEach(n => n.close()));
      break;
    
    case 'DISCONNECT':
      clearInterval(pingInterval);
      pusherWs && pusherWs.close();
      subscribedChannels.clear();
      break;
  }
});

function handleCallInitiated(payload) {
  const callerName = payload.caller?.full_name || 'Appel entrant';
  const callType = payload.type || 'audio';
  const callId = payload.call_id || payload.id;
  const convId = payload.conversation_id;
  const emoji = callType === 'video' ? '' : '';
  
  self.registration.showNotification(callerName, {
    body: `${emoji} Appel ${callType} entrant...`,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: `call-${callId}`,
    requireInteraction: true,
    vibrate: [500, 200, 500],
    actions: [
      { action: 'reject', title: 'Refuser' },
      { action: 'answer', title: 'Répondre' },
    ],
    data: { callId, conversationId: convId, callType, callerName },
  });

  // Notifier les onglets ouverts
  self.clients.matchAll({ type: 'window' }).then(list => {
    list.forEach(client => {
      client.postMessage({ type: 'INCOMING_CALL', payload });
    });
  });
}

function handleMessageSent(payload) {
  const senderName = payload.sender?.full_name || 'Nouveau message';
  const body = payload.type === 'text' ? payload.body : `📎 ${payload.type}`;
  const convId = payload.conversation_id;
  
  self.registration.showNotification(senderName, {
    body,
    icon: '/icons/Icon-192.png',
    tag: `msg-${convId}-${Date.now()}`,
    data: { conversationId: convId },
  });
}

function handleCallStatus(payload) {
  if (['ended', 'rejected', 'missed'].includes(payload.status)) {
    // Fermer la notif d'appel
    self.registration.getNotifications({ tag: `call-${payload.call_id}` })
      .then(notifs => notifs.forEach(n => n.close()));
    
    // Notifier les onglets
    self.clients.matchAll({ type: 'window' }).then(list => {
      list.forEach(client => client.postMessage({ type: 'CALL_STATUS', payload }));
    });
  }
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  
  let urlPath = '/';
  if (event.action === 'answer') {
    urlPath = `/#/conversations/${data.conversationId}?incomingCall=${data.callId}`;
  } else if (event.action === 'reject') {
    // Envoyer reject à tous les onglets ouverts
    self.clients.matchAll({ type: 'window' }).then(list => {
      list.forEach(c => c.postMessage({ type: 'REJECT_CALL', callId: data.callId }));
    });
    return;
  } else if (data.conversationId) {
    urlPath = `/#/conversations/${data.conversationId}`;
  }
  
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const client of list) {
        if ('focus' in client) {
          client.focus();
          client.postMessage({ type: 'NAVIGATE', url: urlPath, data });
          return;
        }
      }
      return clients.openWindow(urlPath);
    })
  );
});