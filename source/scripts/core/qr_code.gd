class_name QrCode
extends RefCounted
## Генератор QR-кода (байтовый режим, коррекция M, версии 1-10): текст -> матрица модулей.

const ECC_PER_BLOCK := [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const BLOCKS := [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const ALIGN := [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]

var size := 0
var modules := PackedByteArray()
var _function := PackedByteArray()


## Матрица size x size, true - тёмный модуль. Пустой массив, если текст не влезает.
static func encode(text: String) -> QrCode:
	var data := text.to_utf8_buffer()
	for version in range(1, 11):
		var capacity := _data_codewords(version) - (2 if version < 10 else 3)
		if data.size() <= capacity:
			var code := QrCode.new()
			code._build(data, version)
			return code
	return null


@warning_ignore("integer_division")
static func _raw_modules(version: int) -> int:
	var result := (16 * version + 128) * version + 64
	if version >= 2:
		var count := version / 7 + 2
		result -= (25 * count - 10) * count - 55
		if version >= 7:
			result -= 36
	return result


@warning_ignore("integer_division")
static func _data_codewords(version: int) -> int:
	return _raw_modules(version) / 8 - int(ECC_PER_BLOCK[version]) * int(BLOCKS[version])


@warning_ignore("integer_division")
func _build(data: PackedByteArray, version: int) -> void:
	size = version * 4 + 17
	var codewords := _make_codewords(data, version)
	var blocks_total: int = BLOCKS[version]
	var ecc_len: int = ECC_PER_BLOCK[version]
	var raw := _raw_modules(version) / 8
	var short_blocks := blocks_total - raw % blocks_total
	var short_len := raw / blocks_total
	var blocks: Array = []
	var divisor := _divisor(ecc_len)
	var offset := 0
	for i in blocks_total:
		var length := short_len - ecc_len + (0 if i < short_blocks else 1)
		var chunk := codewords.slice(offset, offset + length)
		offset += length
		var ecc := _remainder(chunk, divisor)
		if i < short_blocks:
			chunk.append(0)
		chunk.append_array(ecc)
		blocks.append(chunk)
	var result := PackedByteArray()
	for i in (blocks[0] as PackedByteArray).size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= short_blocks:
				result.append((blocks[j] as PackedByteArray)[i])
	var best_mask := 0
	var best_penalty := 1 << 30
	for mask in 8:
		_init_grid()
		_draw_function(version)
		_place(result)
		_apply_mask(mask)
		_draw_format(mask)
		var penalty := _penalty()
		if penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
	_init_grid()
	_draw_function(version)
	_place(result)
	_apply_mask(best_mask)
	_draw_format(best_mask)


func _make_codewords(data: PackedByteArray, version: int) -> PackedByteArray:
	var bits: Array[int] = []
	_append_bits(bits, 4, 4)
	_append_bits(bits, data.size(), 8 if version < 10 else 16)
	for b in data:
		_append_bits(bits, b, 8)
	var capacity_bits := _data_codewords(version) * 8
	_append_bits(bits, 0, mini(4, capacity_bits - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var out := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var v := 0
		for j in 8:
			v = (v << 1) | bits[i + j]
		out.append(v)
	var pad := 0xEC
	while out.size() < capacity_bits / 8:
		out.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	return out


func _append_bits(bits: Array[int], value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


static func _divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 2)
	return result


static func _remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor := b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in divisor.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


func _init_grid() -> void:
	modules = PackedByteArray()
	modules.resize(size * size)
	_function = PackedByteArray()
	_function.resize(size * size)


func _set_function(x: int, y: int, dark: bool) -> void:
	modules[y * size + x] = 1 if dark else 0
	_function[y * size + x] = 1


@warning_ignore("integer_division")
func _draw_function(version: int) -> void:
	for i in size:
		_set_function(6, i, i % 2 == 0)
		_set_function(i, 6, i % 2 == 0)
	_finder(3, 3)
	_finder(size - 4, 3)
	_finder(3, size - 4)
	var positions: Array = ALIGN[version]
	for i in positions.size():
		for j in positions.size():
			if (i == 0 and j == 0) or (i == 0 and j == positions.size() - 1) or (i == positions.size() - 1 and j == 0):
				continue
			_alignment(int(positions[i]), int(positions[j]))
	_draw_format(0)
	if version >= 7:
		var rem := version
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var bits := (version << 12) | rem
		for i in 18:
			var dark := ((bits >> i) & 1) == 1
			var a := size - 11 + i % 3
			var b := i / 3
			_set_function(a, b, dark)
			_set_function(b, a, dark)


func _finder(cx: int, cy: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and x < size and y >= 0 and y < size:
				var dist := maxi(absi(dx), absi(dy))
				_set_function(x, y, dist != 2 and dist != 4)


func _alignment(cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_function(cx + dx, cy + dy, maxi(absi(dx), absi(dy)) != 1)


func _draw_format(mask: int) -> void:
	var data := (0 << 3) | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_function(8, i, ((bits >> i) & 1) == 1)
	_set_function(8, 7, ((bits >> 6) & 1) == 1)
	_set_function(8, 8, ((bits >> 7) & 1) == 1)
	_set_function(7, 8, ((bits >> 8) & 1) == 1)
	for i in range(9, 15):
		_set_function(14 - i, 8, ((bits >> i) & 1) == 1)
	for i in range(0, 8):
		_set_function(size - 1 - i, 8, ((bits >> i) & 1) == 1)
	for i in range(8, 15):
		_set_function(8, size - 15 + i, ((bits >> i) & 1) == 1)
	_set_function(8, size - 8, true)


func _place(data: PackedByteArray) -> void:
	var index := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if _function[y * size + x] == 0 and index < data.size() * 8:
					modules[y * size + x] = (data[index >> 3] >> (7 - (index & 7))) & 1
					index += 1
		right -= 2


@warning_ignore("integer_division")
func _apply_mask(mask: int) -> void:
	for y in size:
		for x in size:
			var invert := false
			match mask:
				0:
					invert = (x + y) % 2 == 0
				1:
					invert = y % 2 == 0
				2:
					invert = x % 3 == 0
				3:
					invert = (x + y) % 3 == 0
				4:
					invert = (x / 3 + y / 2) % 2 == 0
				5:
					invert = x * y % 2 + x * y % 3 == 0
				6:
					invert = (x * y % 2 + x * y % 3) % 2 == 0
				7:
					invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert and _function[y * size + x] == 0:
				modules[y * size + x] ^= 1


@warning_ignore("integer_division")
func _penalty() -> int:
	var result := 0
	for pass_index in 2:
		for a in size:
			var run := 1
			for b in range(1, size):
				var cur := _at(b, a) if pass_index == 0 else _at(a, b)
				var prev := _at(b - 1, a) if pass_index == 0 else _at(a, b - 1)
				if cur == prev:
					run += 1
					if run == 5:
						result += 3
					elif run > 5:
						result += 1
				else:
					run = 1
	for y in size - 1:
		for x in size - 1:
			var c := _at(x, y)
			if c == _at(x + 1, y) and c == _at(x, y + 1) and c == _at(x + 1, y + 1):
				result += 3
	var dark := 0
	for y in size:
		for x in size:
			dark += _at(x, y)
	var total := size * size
	result += ((absi(dark * 20 - total * 10) + total - 1) / total - 1) * 10
	return result


func _at(x: int, y: int) -> int:
	return modules[y * size + x]


func is_dark(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size and modules[y * size + x] == 1
