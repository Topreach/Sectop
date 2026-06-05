// Danger Emergence System - Service Worker
// Implements offline-first caching strategy for emergency resilience

const CACHE_NAME = 'danger-emergence-v1';
const STATIC_CACHE = 'danger-emergence-static-v1';
const DYNAMIC_CACHE = 'danger-emergence-dynamic-v1';
const MAP_TILES_CACHE = 'danger-emergence-tiles-v1';
const API_CACHE = 'danger-emergence-api-v1';

// Static assets to pre-cache on install
const PRECACHE_ASSETS = [
  '/',
  '/index.html',
  '/main.dart.js',
  '/manifest.json',
  '/icons/icon-192x192.png',
  '/icons/icon-512x512.png',
  '/icons/sos-shortcut.png',
  '/icons/map-shortcut.png',
  '/icons/contacts-shortcut.png',
];

// Install event - pre-cache critical assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => {
      return cache.addAll(PRECACHE_ASSETS);
    }).then(() => {
      // Skip waiting to activate immediately
      return self.skipWaiting();
    })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  const cacheWhitelist = [STATIC_CACHE, DYNAMIC_CACHE, MAP_TILES_CACHE, API_CACHE];
  
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (!cacheWhitelist.includes(cacheName)) {
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      // Claim all clients immediately
      return self.clients.claim();
    })
  );
});

// Fetch event - strategic caching based on resource type
self.addEventListener('fetch', (event) => {
  const requestUrl = new URL(event.request.url);
  
  // Skip non-GET requests
  if (event.request.method !== 'GET') return;
  
  // API requests - Network First with fallback
  if (requestUrl.pathname.startsWith('/api/')) {
    event.respondWith(networkFirstStrategy(event.request, API_CACHE));
    return;
  }
  
  // Map tiles - Cache First with background refresh
  if (requestUrl.pathname.includes('/tiles/') || requestUrl.pathname.endsWith('.pmtiles')) {
    event.respondWith(cacheFirstStrategy(event.request, MAP_TILES_CACHE));
    return;
  }
  
  // Static assets - Cache First
  if (isStaticAsset(requestUrl)) {
    event.respondWith(cacheFirstStrategy(event.request, STATIC_CACHE));
    return;
  }
  
  // Navigation requests - Network First with offline fallback
  if (event.request.mode === 'navigate') {
    event.respondWith(networkFirstStrategy(event.request, DYNAMIC_CACHE));
    return;
  }
  
  // Everything else - Network First
  event.respondWith(networkFirstStrategy(event.request, DYNAMIC_CACHE));
});

// Cache First strategy - for static assets and map tiles
async function cacheFirstStrategy(request, cacheName) {
  const cachedResponse = await caches.match(request);
  
  if (cachedResponse) {
    // Return cached response immediately
    return cachedResponse;
  }
  
  try {
    const networkResponse = await fetch(request);
    if (networkResponse && networkResponse.status === 200) {
      const cache = await caches.open(cacheName);
      cache.put(request, networkResponse.clone());
    }
    return networkResponse;
  } catch (error) {
    // Return offline fallback for navigation requests
    if (request.mode === 'navigate') {
      return caches.match('/index.html');
    }
    throw error;
  }
}

// Network First strategy - for API calls and dynamic content
async function networkFirstStrategy(request, cacheName) {
  try {
    const networkResponse = await fetch(request);
    
    if (networkResponse && networkResponse.status === 200) {
      const cache = await caches.open(cacheName);
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    const cachedResponse = await caches.match(request);
    
    if (cachedResponse) {
      return cachedResponse;
    }
    
    // Return offline fallback
    if (request.mode === 'navigate') {
      return caches.match('/index.html');
    }
    
    // Return a generic offline response for API calls
    return new Response(
      JSON.stringify({ error: 'offline', message: 'No internet connection' }),
      { status: 503, headers: { 'Content-Type': 'application/json' } }
    );
  }
}

// Helper to check if request is for a static asset
function isStaticAsset(url) {
  const staticExtensions = [
    '.js', '.css', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico',
    '.woff', '.woff2', '.ttf', '.eot',
  ];
  
  return staticExtensions.some(ext => url.pathname.endsWith(ext));
}

// Background sync for offline messages
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-messages') {
    event.waitUntil(syncOfflineMessages());
  }
});

async function syncOfflineMessages() {
  try {
    const cache = await caches.open(API_CACHE);
    const requests = await cache.keys();
    
    for (const request of requests) {
      if (request.url.includes('/api/messages')) {
        const cachedResponse = await cache.match(request);
        if (cachedResponse) {
          // Attempt to send cached messages
          const data = await cachedResponse.json();
          await fetch(request.url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
          });
        }
      }
    }
  } catch (error) {
    console.error('Background sync failed:', error);
  }
}

// Push notification handler
self.addEventListener('push', (event) => {
  const data = event.data.json();
  
  const options = {
    body: data.body,
    icon: '/icons/icon-192x192.png',
    badge: '/icons/badge.png',
    vibrate: [200, 100, 200],
    data: {
      url: data.url || '/',
      alertId: data.alertId,
    },
    actions: [
      { action: 'view', title: 'View Alert' },
      { action: 'acknowledge', title: 'Acknowledge' },
    ],
    tag: `alert-${data.alertId}`,
    renotify: true,
    requireInteraction: true,
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// Notification click handler
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  if (event.action === 'acknowledge') {
    // Send acknowledgment via API
    const alertId = event.notification.data.alertId;
    fetch(`/api/alerts/${alertId}/acknowledge`, { method: 'POST' });
  }

  // Focus or open the app
  event.waitUntil(
    clients.matchAll({ type: 'window' }).then((clientList) => {
      if (clientList.length > 0) {
        return clientList[0].focus();
      }
      return clients.openWindow(event.notification.data.url);
    })
  );
});
