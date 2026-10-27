@tool
extends PrimitiveMesh
class_name VoxelTorusMesh

## Blocky stand-in for TorusMesh with the same settings (inner_radius, outer_radius),
## lying flat in the XZ plane like TorusMesh.

@export var inner_radius: float = 0.5:
	set(v):
		inner_radius = v
		request_update()
@export var outer_radius: float = 1.0:
	set(v):
		outer_radius = v
		request_update()
# Accepted for drop-in compatibility with TorusMesh; voxel resolution is automatic
var rings: int = 64
var ring_segments: int = 32

func _create_mesh_array() -> Array:
	var inner := VoxelMeshBuilder.quantize(minf(inner_radius, outer_radius))
	var outer := maxf(VoxelMeshBuilder.quantize(maxf(inner_radius, outer_radius)), 0.002)
	var centre_r := (inner + outer) * 0.5
	var tube := maxf((outer - inner) * 0.5, 0.001)
	# At least ~2 blocks through the tube, at most ~16 across the ring (keeps thin rings cheap)
	var voxel := maxf(tube * 2.0 / 2.0, outer * 2.0 / 16.0)
	var key := "torus|%.3f|%.3f" % [inner, outer]
	return VoxelMeshBuilder.build(key, Vector3(outer * 2.0, maxf(tube * 2.0, voxel), outer * 2.0), voxel, func(p: Vector3) -> bool:
		var d := Vector2(p.x, p.z).length() - centre_r
		# Half-voxel tolerance so very thin rings stay connected
		return d * d + p.y * p.y <= pow(tube + voxel * 0.5, 2.0))
