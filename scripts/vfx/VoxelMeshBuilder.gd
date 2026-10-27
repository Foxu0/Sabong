extends RefCounted
class_name VoxelMeshBuilder

## VoxelMeshBuilder — turns a shape test into a blocky voxel mesh so combat effects
## match the voxel world instead of looking like smooth flat-colored primitives.
## Only faces that touch empty space are emitted, and each face direction gets a baked
## brightness (vertex color) so blocks read as solid even with unshaded materials.
## Results are cached by shape key: effects rebuild the same shapes over and over.

const MAX_CACHED_SHAPES := 512

# +Y, -Y, +X, -X, +Z, -Z
const _DIRS: Array[Vector3i] = [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const _SHADE: Array[float] = [1.0, 0.58, 0.86, 0.86, 0.72, 0.72]

static var _cache: Dictionary = {}
# Per direction: 4 unit corner offsets (half-voxel units) wound for Godot's clockwise front faces
static var _corners: Array = []

## Snaps a size to geometric steps ~15% apart so effects with random sizes reuse cached shapes.
static func quantize(v: float) -> float:
	if v <= 0.0001:
		return 0.0
	return pow(1.15, roundf(log(v) / log(1.15)))

## size: bounding box of the shape (centred on the origin); voxel: cube edge length;
## occupied: Callable(Vector3 cell_centre) -> bool
static func build(key: String, size: Vector3, voxel: float, occupied: Callable) -> Array:
	if _cache.has(key):
		return _cache[key]
	_ensure_corners()
	voxel = maxf(voxel, 0.005)
	var nx := maxi(1, ceili(size.x / voxel - 0.001))
	var ny := maxi(1, ceili(size.y / voxel - 0.001))
	var nz := maxi(1, ceili(size.z / voxel - 0.001))
	var origin := -Vector3(nx, ny, nz) * voxel * 0.5 + Vector3.ONE * voxel * 0.5
	var grid := PackedByteArray()
	grid.resize(nx * ny * nz)
	var any := false
	for x in nx:
		for y in ny:
			for z in nz:
				if occupied.call(origin + Vector3(x, y, z) * voxel):
					grid[(x * ny + y) * nz + z] = 1
					any = true
	if not any:
		# Tiny shapes still show one block instead of vanishing
		grid[((nx / 2) * ny + ny / 2) * nz + nz / 2] = 1

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var h := voxel * 0.5
	for x in nx:
		for y in ny:
			for z in nz:
				if grid[(x * ny + y) * nz + z] == 0:
					continue
				var centre := origin + Vector3(x, y, z) * voxel
				for d in 6:
					var nb: Vector3i = _DIRS[d]
					var bx := x + nb.x
					var by := y + nb.y
					var bz := z + nb.z
					if bx >= 0 and by >= 0 and bz >= 0 and bx < nx and by < ny and bz < nz and grid[(bx * ny + by) * nz + bz] == 1:
						continue
					var base := verts.size()
					var normal := Vector3(nb)
					var shade := _SHADE[d]
					var col := Color(shade, shade, shade, 1.0)
					for off in _corners[d]:
						verts.append(centre + off * h)
						normals.append(normal)
						colors.append(col)
					indices.append(base)
					indices.append(base + 1)
					indices.append(base + 2)
					indices.append(base)
					indices.append(base + 2)
					indices.append(base + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if _cache.size() >= MAX_CACHED_SHAPES:
		_cache.clear()
	_cache[key] = arrays
	return arrays

static func _ensure_corners() -> void:
	if not _corners.is_empty():
		return
	for d in 6:
		var n := Vector3(_DIRS[d])
		var u := Vector3(n.y, n.z, n.x)
		var v := n.cross(u)
		var quad: Array[Vector3] = [n - u - v, n + u - v, n + u + v, n - u + v]
		# Godot treats clockwise triangles as front-facing: flip if this winding faces inward
		if (quad[1] - quad[0]).cross(quad[2] - quad[0]).dot(n) > 0.0:
			quad = [quad[0], quad[3], quad[2], quad[1]]
		_corners.append(quad)
