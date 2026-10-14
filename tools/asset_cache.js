// CacheStorage keeps binary resources that the HTTP cache may evict between launches.
function installAssetCache(urls) {
    const keep = new Set(urls.map(url => new URL(url, document.baseURI).href));
    let writable = true;
    const ready = (async () => {
        try {
            if (!window.caches) return null;
            const scope = new URL('.', document.baseURI).pathname;
            const cache = await caches.open('trash-squad-packs-v1:' + scope);
            for (const request of await cache.keys()) {
                if (!keep.has(request.url)) await cache.delete(request);
            }
            return cache;
        } catch (_) { return null; }
    })();
    return {
        async read(url) {
            try { const cache = await ready; return cache ? await cache.match(url) : null; }
            catch (_) { return null; }
        },
        async write(url, bytes) {
            if (!writable) return;
            try {
                const cache = await ready;
                if (cache) await cache.put(url, new Response(bytes, {headers: {'Content-Type': 'application/octet-stream', 'Content-Length': String(bytes.length)}}));
            } catch (_) { writable = false; }
        },
        async drop(url) {
            try { const cache = await ready; if (cache) await cache.delete(url); } catch (_) {}
        },
    };
}
