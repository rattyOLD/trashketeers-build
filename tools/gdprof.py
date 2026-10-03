#!/usr/bin/env python3
"""Minimal Godot 4 remote-debugger server: enables the script profiler for a window
and prints the accumulated per-function totals.  Usage: gdprof.py PORT WARMUP SECONDS"""
import socket, struct, sys, time, select

PORT, WARMUP, SECS = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
F64 = 1 << 16


def dec(b, o):
    h = struct.unpack_from('<I', b, o)[0]; o += 4
    t = h & 0xFF
    if t == 0: return None, o
    if t == 1: return bool(struct.unpack_from('<I', b, o)[0]), o + 4
    if t == 2:
        if h & F64: return struct.unpack_from('<q', b, o)[0], o + 8
        return struct.unpack_from('<i', b, o)[0], o + 4
    if t == 3:
        if h & F64: return struct.unpack_from('<d', b, o)[0], o + 8
        return struct.unpack_from('<f', b, o)[0], o + 4
    if t in (4, 21, 22):
        if t == 22:
            raise ValueError('nodepath')
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        s = b[o:o + n].decode('utf-8', 'replace'); o += (n + 3) & ~3
        return s, o
    fixed = {5: 8, 6: 8, 7: 16, 8: 16, 9: 12, 10: 12, 11: 24, 12: 16, 13: 16, 14: 16, 15: 16, 16: 24, 17: 36, 18: 48, 19: 64, 20: 16, 23: 8}
    if t in fixed:
        sz = fixed[t] * (2 if (h & F64 and t not in (6, 8, 10, 13, 20, 23)) else 1)
        return ('<v%d>' % t), o + sz
    if t == 28:
        n = struct.unpack_from('<I', b, o)[0] & 0x7FFFFFFF; o += 4
        if (h >> 16) & 3:  # typed array: skip element type info
            kind = (h >> 16) & 3
            if kind == 1: o += 4
            else:
                l = struct.unpack_from('<I', b, o)[0]; o += 4 + ((l + 3) & ~3)
        out = []
        for _ in range(n):
            v, o = dec(b, o); out.append(v)
        return out, o
    if t == 27:
        n = struct.unpack_from('<I', b, o)[0] & 0x7FFFFFFF; o += 4
        d = {}
        for _ in range(n):
            k, o = dec(b, o); v, o = dec(b, o); d[str(k)] = v
        return d, o
    if t in (29, 30, 31, 32, 33, 35, 36, 37, 38):
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        es = {29: 1, 30: 4, 31: 8, 32: 4, 33: 8, 35: 8, 36: 12, 37: 16, 38: 16}[t]
        return ('<packed%d>' % t), o + ((n * es + 3) & ~3)
    if t == 34:
        n = struct.unpack_from('<I', b, o)[0]; o += 4
        for _ in range(n):
            l = struct.unpack_from('<I', b, o)[0]; o += 4 + ((l + 3) & ~3)
        return '<pstr>', o
    raise ValueError('type %d' % t)


def enc(v):
    if isinstance(v, bool): return struct.pack('<II', 1, int(v))
    if isinstance(v, int): return struct.pack('<Ii', 2, v)
    if isinstance(v, str):
        e = v.encode(); return struct.pack('<II', 4, len(e)) + e + b'\0' * ((4 - len(e) % 4) % 4)
    if isinstance(v, list):
        return struct.pack('<II', 28, len(v)) + b''.join(enc(x) for x in v)
    raise TypeError(v)


srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', PORT)); srv.listen(1)
srv.settimeout(120)
c, _ = srv.accept()
buf = b''
sigs = {}
thread = None
t0 = time.time()
state = 0
total = None
frames = []
NAMES = {}


def send(cmd, data):
    m = enc([cmd, thread or 1, data])
    c.sendall(struct.pack('<I', len(m)) + m)


while True:
    r, _, _ = select.select([c], [], [], 0.05)
    if r:
        d = c.recv(1 << 20)
        if not d: break
        buf += d
    while len(buf) >= 4:
        n = struct.unpack_from('<I', buf)[0]
        if len(buf) < 4 + n: break
        body = buf[4:4 + n]; buf = buf[4 + n:]
        try:
            msg, _ = dec(body, 0)
        except Exception:
            continue
        name, th, data = msg[0], msg[1], msg[2]
        NAMES[name] = NAMES.get(name, 0) + 1
        if name == 'performance:profile_frame' and isinstance(th, int): thread = th
        if name == 'debug_enter':
            print('DEBUG_ENTER', data)
            send('get_stack_dump', [])
        if name == 'stack_dump':
            print('STACK', data)
        if name == 'servers:function_signature':
            sigs[data[1]] = data[0]
        elif name == 'servers:profile_frame':
            frames.append(data[:6])
        elif name == 'servers:profile_total':
            total = data
        elif name == 'output':
            for line in (data[0] if data and isinstance(data[0], list) else []):
                if isinstance(line, str) and 'PROF' in line: print(line.strip())
    el = time.time() - t0
    if state == 0 and el > WARMUP and thread is not None:
        send('profiler:servers', [True, [256, False]]); state = 1; t1 = time.time()
    elif state == 1 and time.time() - t1 > SECS:
        send('profiler:servers', [False]); state = 2; t2 = time.time()
    elif state == 2 and (total is not None or time.time() - t2 > 5):
        break

print('NAMES', NAMES, 'thread', thread, 'state', state)
if total is None:
    print('no total; frames', len(frames)); sys.exit(1)
nf = max(len(frames), 1)
print('frames %d  avg frame %.2fms process %.2fms physics %.2fms script %.2fms' % (
    nf, *(sum(f[i] for f in frames) / nf * 1000 for i in (1, 2, 3, 5))))
idx = 6
ns = total[idx]; idx += 1
for _ in range(ns):
    name = total[idx]; sub = total[idx + 1]; idx += 2
    items = [(total[idx + 2 * j], total[idx + 2 * j + 1]) for j in range(sub // 2)]
    idx += sub
    print('server', name, ' '.join('%s=%.2fms' % (a, b * 1000 / nf) for a, b in items))
fs = total[idx]; idx += 1
rows = []
for j in range(fs // 5):
    sid, calls, self_t, tot_t, _int = total[idx:idx + 5]; idx += 5
    rows.append((self_t, tot_t, calls, sigs.get(sid, str(sid))))
rows.sort(reverse=True)
print('%-8s %-8s %-8s %s' % ('self/fr', 'tot/fr', 'calls/fr', 'function'))
for s, t, cnt, n in rows[:60]:
    print('%7.3f  %7.3f  %7.1f  %s' % (s * 1000 / nf, t * 1000 / nf, cnt / nf, n))
