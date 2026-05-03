let ws = null;
let authToken = null;
let reconnectTimer = null;

function connectWS() {
  if (ws && ws.readyState === WebSocket.OPEN) return;
  
  ws = new WebSocket(
    `ws://192.168.100.195:8080/app/xtsedffitwzc6vpwl7tz?protocol=7&client=js&version=8.3.0`
  );

  ws.onopen = () => {
    clearTimeout(reconnectTimer);
    // S'abonner aux canaux presence de l'utilisateur
    if (authToken) subscribeToUserChannel();
  };

  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    handleReverbEvent(data);
  };

  ws.onclose = () => {
    // Reconnexion automatique toutes les 5 secondes
    reconnectTimer = setTimeout(connectWS, 5000);
  };
}

function handleReverbEvent(data) {
  if (data.event === 'pusher:connection_established') return;
  
  // Décoder le payload Pusher
  let payload = {};
  try { payload = JSON.parse(data.data || '{}'); } catch(e) {}

  if (data.event === 'App\\Events\\CallInitiated' || 
      data.event === 'call.initiated') {
    showCallNotification(payload);
  }
  
  if (data.event === 'App\\Events\\MessageSent' || 
      data.event === 'message.sent') {
    showMessageNotification(payload);
  }
}

function showCallNotification(payload) {
  const callerName = payload.caller?.full_name || 'Appel entrant';
  const callType = payload.type === 'video' ? 'Appel vidéo' : 'Appel audio';
  
  self.registration.showNotification(callerName, {
    body: `${callType} entrant...`,
    icon: '/icons/Icon-192.png',
    tag: `call-${payload.call_id}`,
    requireInteraction: true,
    actions: [
      { action: 'reject', title: 'Refuser' },
      { action: 'answer', title: 'Répondre' },
    ],
    data: payload,
  });
}

// Recevoir le token depuis l'app principale
self.addEventListener('message', (event) => {
  if (event.data?.type === 'SET_AUTH_TOKEN') {
    authToken = event.data.token;
    connectWS();
  }
  if (event.data?.type === 'DISCONNECT') {
    ws?.close();
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  
  const url = event.action === 'answer' 
    ? `/conversations/${data.conversation_id}?answer=${data.call_id}`
    : `/`;

  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(list => {
      for (const client of list) {
        if ('focus' in client) { client.focus(); client.postMessage({ type: 'NAVIGATE', url, data }); return; }
      }
      return clients.openWindow(url);
    })
  );
});