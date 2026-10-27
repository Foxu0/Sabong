@tool
extends PrimitiveMesh
class_name VoxelSphereMesh

## Blocky stand-in for SphereMesh with the same settings (radius, height, is_hemisphere).

@export var radius: float = 0.5:
	set(v):
		radius = v
		request_update()
@export var height: float = 1.0:
	set(v):
		height = v
		request_update()
@export var is_hemisphere: bool = false:
	set(v):
		is_hemisphere = v
		request_update()
# Accepted for drop-in compatibility with SphereMesh; voxel resolution is automatic
var rings: int = 32
var radial_segments: int = 64

const VOXELS_ACROSS := 8.0

func _create_mesh_array() -> Array:
	var r := maxf(VoxelMeshBuilder.quantize(radius), 0.001)
	var hy := maxf(VoxelMeshBuilder.quantize(height) * 0.5, 0.001)
	var voxel := maxf(r * 2.0, hy * 2.0) / VOXELS_ACROSS
	var hemi := is_hemisphere
	var key := "sphere|%.3f|%.3f|%s" % [r, hy, hemi]
	return VoxelMeshBuilder.build(key, Vector3(r * 2.0, hy * 2.0, r * 2.0), voxel, func(p: Vector3) -> bool:
		if hemi and p.y < 0.0:
			return false
		return (p.x * p.x) / (r * r) + (p.y * p.y) / (hy * hy) + (p.z * p.z) / (r * r) <= 1.0)
