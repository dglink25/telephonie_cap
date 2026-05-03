importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyClakb5nj3zT0URgbrtC6v35OmcTB9yMdY',
  authDomain: 'cap-telephonie.firebaseapp.com',
  projectId: 'cap-telephonie',
  storageBucket: 'cap-telephonie.firebasestorage.app',
  messagingSenderId: '618091922594',
  appId: '1:618091922594:web:a61e187aac70e8afaa43fb',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[SW] Message arriere-plan:', payload);

  const data = payload.data || {};
  const type = data.type || '';

  let title = payload.notification && payload.notification.title
    ? payload.notification.title
    : 'Telephonie CAP';
  let body = payload.notification && payload.notification.body
    ? payload.notification.body
    : '';
  let tag = 'default';
  let requireInteraction = false;
  let actions = [];
  let vibrate = [200, 100, 200];

  if (type === 'incoming_call') {
    var callType = data.call_type || 'audio';
    var emoji = callType === 'video' ? 'Video' : 'Audio';
    title = emoji + ' - Appel entrant';
    body = (data.caller_name || 'Quelqun') + ' vous appelle';
    tag = 'call-' + (data.call_id || '0');
    requireInteraction = true;
    vibrate = [500, 200, 500, 200, 500];
    actions = [
      { action: 'reject', title: 'Refuser' },
      { action: 'answer', title: 'Repondre' }
    ];
  } else if (type === 'new_message') {
    title = data.sender_name || 'Nouveau message';
    body = data.body || 'Nouveau message';
    tag = 'msg-' + (data.conversation_id || '0');
  }

  return self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: tag,
    requireInteraction: requireInteraction,
    actions: actions,
    vibrate: vibrate,
    data: data,
    timestamp: Date.now()
  });
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();

  var data = event.notification.data || {};
  var action = event.action;
  var type = data.type || '';
  var url = '/';

  if (type === 'incoming_call') {
    if (action === 'answer') {
      url = '/conversations/' + data.conversation_id + '?action=answer&call_id=' + data.call_id;
    } else if (action === 'reject') {
      event.waitUntil(
        clients.matchAll({ type: 'window' }).then(function(clientList) {
          for (var i = 0; i < clientList.length; i++) {
            clientList[i].postMessage({ type: 'REJECT_CALL', callId: data.call_id });
          }
        })
      );
      return;
    } else {
      url = '/conversations/' + data.conversation_id;
    }
  } else if (type === 'new_message') {
    url = '/conversations/' + data.conversation_id;
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        if (client.url.indexOf(self.location.origin) !== -1 && 'focus' in client) {
          client.focus();
          client.postMessage({ type: 'NAVIGATE', url: url, data: data });
          return;
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});

self.addEventListener('activate', function(event) {
  console.log('[SW] Active');
  event.waitUntil(clients.claim());
});

self.addEventListener('install', function(event) {
  console.log('[SW] Installe');
  self.skipWaiting();
});