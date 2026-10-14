from pathlib import Path
import collections, hashlib, json, re, struct


def read_pack(path):
    raw = Path(path).read_bytes()
    assert struct.unpack_from('<II', raw) == (0x43504447, 2)
    assert struct.unpack_from('<I', raw, 20)[0] == 0
    base = struct.unpack_from('<Q', raw, 24)[0]
    count = struct.unpack_from('<I', raw, 96)[0]
    pos = 100
    files = {}
    for _ in range(count):
        length = struct.unpack_from('<I', raw, pos)[0]; pos += 4
        name = raw[pos:pos + length].rstrip(b'\0').decode(); pos += length
        offset, size = struct.unpack_from('<QQ', raw, pos); pos += 16
        digest = raw[pos:pos + 16]; pos += 16
        flags = struct.unpack_from('<I', raw, pos)[0]; pos += 4
        assert flags == 0
        data = raw[base + offset:base + offset + size]
        assert hashlib.md5(data).digest() == digest, name
        files[name] = data
    return raw[:96], files


def write_pack(header, files, directory_unit=4096):
    names = sorted(files, key=lambda p: (not p.startswith(('.godot/imported/', 'assets/')), p))
    directory = []
    offset = 0
    for name in names:
        encoded = name.encode() + b'\0'
        encoded += b'\0' * (-len(encoded) % 4)
        data = files[name]
        directory.append(struct.pack('<I', len(encoded)) + encoded + struct.pack('<QQ', offset, len(data)) + hashlib.md5(data).digest() + struct.pack('<I', 0))
        offset += (len(data) + 15) // 16 * 16
    table = struct.pack('<I', len(names)) + b''.join(directory)
    # Fixed directory space keeps unchanged asset payloads at the same offsets across code releases.
    base = (96 + len(table) + directory_unit - 1) // directory_unit * directory_unit
    out = bytearray(base + offset)
    out[:96] = header
    struct.pack_into('<Q', out, 24, base)
    out[96:96 + len(table)] = table
    at = base
    for name in names:
        data = files[name]
        out[at:at + len(data)] = data
        at += (len(data) + 15) // 16 * 16
    return bytes(out)


def split_pack(path, source):
    header, files = read_pack(path)
    owners = {}
    for name, data in files.items():
        if name.startswith('assets/') and name.endswith('.import'):
            for match in re.finditer(r'"(res://\.godot/imported/[^"\n]+)"', data.decode(errors='replace')):
                owners[match[1][6:]] = name[:-7]
    frames = json.loads((Path(source) / 'data/frames.json').read_text())['sheets']
    enemies = json.loads((Path(source) / 'data/enemies.json').read_text())['enemies']
    path_enemies = collections.defaultdict(set)
    def paths(value):
        if isinstance(value, str) and value.startswith('res://assets/'):
            yield value[6:]
        elif isinstance(value, dict):
            for child in value.values(): yield from paths(child)
        elif isinstance(value, list):
            for child in value: yield from paths(child)
    for enemy in enemies:
        identity = enemy['enemy_id']
        for asset in paths(enemy): path_enemies[asset].add(identity)
        for asset in paths(frames.get(enemy.get('frames', ''), {})): path_enemies[asset].add(identity)
    groups = collections.defaultdict(dict)
    resource_groups = {}
    enemy_groups = collections.defaultdict(set)
    boot_pigs = {'assets/enemies/pig_angry.png', 'assets/enemies/pig_default.png', 'assets/enemies/pig_heavy.png', 'assets/enemies/pig_royal.png', 'assets/enemies/razor_card.png', 'assets/enemies/casino_chip.png'}
    # Legacy rig enemies are warmed by Game.start before chapter-specific waves.
    boot_pigs.update(asset for enemy in enemies if not enemy.get('frames') for asset in paths(enemy))
    for name, data in files.items():
        asset = owners.get(name, name)
        group = 'boot'
        if asset.startswith('assets/heroes/tactical/') and not asset.split('/')[-1].startswith('raccoon_') and not asset.endswith('_idle.png'):
            group = 'heroes'
        elif asset.startswith('assets/ui/loading/') and asset.split('/')[-1].startswith('bg_'):
            group = 'loading_' + asset.split('/')[-1].split('_')[1]
        elif asset.startswith('assets/raid/') or asset.startswith('assets/bosses/ice_dragon'):
            group = 'raid'
        elif asset.startswith(('assets/enemies/', 'assets/bosses/')) and asset not in boot_pigs:
            identities = path_enemies.get(asset, set())
            group = 'enemy_' + next(iter(identities)) if len(identities) == 1 else 'enemy_common'
            for identity in identities: enemy_groups[identity].add(group)
        elif asset.startswith(('assets/props/', 'assets/biome/', 'assets/world/', 'assets/terrain/', 'assets/district/')) and asset != 'assets/world/battle_wear.png':
            group = 'world'
        elif asset.startswith('assets/maps/') and not asset.endswith('/card.png'):
            group = 'world'
        # Resource remaps stay in the bootstrap so their names and UID lookup remain available.
        if name.endswith('.import') or name.endswith('.remap'):
            group = 'boot'
        groups[group][name] = data
        if group != 'boot':
            resource_groups['res://' + asset] = group
    manifests = {'resources': resource_groups, 'enemies': {k: sorted(v) for k, v in enemy_groups.items()}}
    packed = {group: write_pack(header, members, 1048576 if group == 'boot' else 4096) for group, members in groups.items()}
    assert sum(len(members) for members in groups.values()) == len(files)
    for group, raw in packed.items():
        temporary = Path(source).parent / ('verify-' + group + '.pck')
        temporary.write_bytes(raw)
        _, decoded = read_pack(temporary)
        assert decoded == groups[group], group
        temporary.unlink()
    return packed, manifests


if __name__ == '__main__':
    import sys
    packed, manifest = split_pack(sys.argv[1], sys.argv[2])
    out = Path(sys.argv[3]); out.mkdir(parents=True, exist_ok=True)
    for group, raw in packed.items(): (out / (group + '.pck')).write_bytes(raw)
    (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False))
    print('PACK_GROUPS', {key: round(len(raw) / 1048576, 2) for key, raw in packed.items()})
