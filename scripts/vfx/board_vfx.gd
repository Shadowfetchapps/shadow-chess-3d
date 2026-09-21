class_name BoardVFX
extends Node3D

var _capture: GPUParticles3D
var _land: GPUParticles3D


func _ready() -> void:
	_capture = _make_burst(Color(1.0, 0.62, 0.28), 28, 0.42)
	_land = _make_burst(Color(0.86, 0.72, 0.42), 14, 0.28)
	add_child(_capture)
	add_child(_land)


func play_capture(pos: Vector3) -> void:
	_fire(_capture, pos + Vector3(0, 0.22, 0))


func play_land(pos: Vector3) -> void:
	_fire(_land, pos + Vector3(0, 0.04, 0))


func _fire(p: GPUParticles3D, pos: Vector3) -> void:
	p.global_position = pos
	p.restart()
	p.emitting = true


func _make_burst(color: Color, amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 58.0
	mat.initial_velocity_min = 0.55
	mat.initial_velocity_max = 2.1
	mat.gravity = Vector3(0, -5.2, 0)
	mat.scale_min = 0.018
	mat.scale_max = 0.055
	mat.color = color
	p.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 8
	mesh.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = color
	smat.emission_enabled = true
	smat.emission = color
	smat.emission_energy_multiplier = 1.8
	smat.roughness = 0.35
	mesh.material = smat
	p.draw_pass_1 = mesh
	return p
