// Additional packs are downloaded only when a screen needs them; buffers are released after MEMFS owns them.
function installResourcePacks(manifest, engineGetter) {
    const states = new Map();
    const tickets = new Map();
    let serial = 0;
    // One extra pack at a time also bounds decompression and MEMFS transfer memory.
    let queue = Promise.resolve();
    function enqueue(job) {
        const running = queue.then(job);
        queue = running.then(() => undefined, () => undefined);
        return running;
    }
    function start(groups) {
        const selected = [...new Set(groups)].filter(group => manifest.groups[group]);
        const ticket = {state: 'loading', loaded: 0, total: 0, files: [], error: ''};
        const id = ++serial;
        tickets.set(id, ticket);
        const jobs = selected.map(group => {
            let entry = states.get(group);
            if (!entry || entry.error) {
                entry = {loaded: 0, total: manifest.groups[group].parts.reduce((n, p) => n + p.bytes, 0), error: ''};
                states.set(group, entry);
                const key = 'bundle:' + group;
                FILES[key] = {parts: manifest.groups[group].parts};
                loadedParts[key] = FILES[key].parts.map(() => 0);
                loaded[key] = 0;
                entry.promise = enqueue(() => download(key)).then(bytes => {
                    const path = '/tmp/trash-' + group + '.pck';
                    engineGetter().copyToFS(path, bytes);
                    entry.loaded = entry.total;
                    return {group, path};
                }).catch(error => {
                    entry.error = String(error);
                    throw error;
                });
            }
            ticket.total += entry.total;
            return entry.promise;
        });
        Promise.all(jobs).then(files => { ticket.files = files; ticket.state = 'ready'; })
            .catch(error => { ticket.error = String(error); ticket.state = 'error'; });
        const poll = setInterval(() => {
            ticket.loaded = selected.reduce((n, group) => {
                const entry = states.get(group);
                return n + Math.min(entry.total, Math.max(entry.loaded, loaded['bundle:' + group] || 0));
            }, 0);
            if (ticket.state !== 'loading') clearInterval(poll);
        }, 100);
        return id;
    }
    return {
        resources: manifest.resources,
        urls: Object.values(manifest.groups).flatMap(group => group.parts.map(part => part.url)),
        start,
        status(id) { return tickets.get(id) || {state: 'error', error: 'Unknown download'}; },
        enemyGroups(ids) { return [...new Set(ids.flatMap(id => manifest.enemies[id] || []))]; },
    };
}
