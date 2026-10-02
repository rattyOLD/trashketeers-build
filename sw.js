// v2 (03.10): после обновления сбрасываем кеши и перезагружаем открытые вкладки, чтобы не оставалась старая страница загрузки.
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (event) {
	event.waitUntil((async function () {
		try { const keys = await caches.keys(); await Promise.all(keys.map(function (k) { return caches.delete(k); })); } catch (e) {}
		await self.clients.claim();
		try {
			const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
			list.forEach(function (c) { try { c.navigate(c.url); } catch (e) {} });
		} catch (e) {}
	})());
});
self.addEventListener('fetch', function () {});
