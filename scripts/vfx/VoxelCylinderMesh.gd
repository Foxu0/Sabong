@tool
extends PrimitiveMesh
class_name VoxelCylinderMesh

## Blocky stand-in for CylinderMesh with the same settings (top_radius, bottom_radius,
## height), standing along the Y axis like CylinderMesh. Cones and beams included.

@export var top_radius: float = 0.5:
	set(v):
		top_radius = v
		request_update()
@export var bottom_radius: float = 0.5:
	set(v):
		bottom_radius = v
		request_update()
@export var height: float = 2.0:
	set(v):
		height = v
		request_update()
# Accepted for drop-in compatibility with CylinderMesh; voxel resolution is automatic
var radial_segments: int = 64
var rings: int = 4
var cap_top: bool = true
var cap_bottom: bool = true

func _create_mesh_array() -> Array:
	var top := VoxelMeshBuilder.quantize(maxf(top_radius, 0.0))
	var bottom := VoxelMeshBuilder.quantize(maxf(bottom_radius, 0.0))
	var max_r := maxf(maxf(top, bottom), 0.002)
	var h := maxf(VoxelMeshBuilder.quantize(height), 0.002)
	# ~4 blocks across the widest part; long beams capped at ~20 blocks
	var voxel := maxf(max_r * 2.0 / 4.0, h / 20.0)
	var key := "cyl|%.3f|%.3f|%.3f" % [top, bottom, h]
	return VoxelMeshBuilder.build(key, Vector3(max_r * 2.0, h, max_r * 2.0), voxel, func(p: Vector3) -> bool:
		var t := clampf((p.y + h * 0.5) / h, 0.0, 1.0)
		var r := lerpf(bottom, top, t)
		return Vector2(p.x, p.z).length() <= r + voxel * 0.35)
