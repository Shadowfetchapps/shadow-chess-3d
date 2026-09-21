class_name TestPresentation
extends RefCounted

var _passed := 0
var _failed := 0
var _errors: PackedStringArray = PackedStringArray()


func run_all() -> bool:
	_passed = 0
	_failed = 0
	_errors.clear()
	print("presentation")
	_materials_cached()
	_piece_meshes_cached()
	print("\n==============================")
	print("Shadow Chess presentation  —  %d passed, %d failed" % [_passed, _failed])
	for e in _errors:
		print("  FAIL  ", e)
	print("==============================\n")
	return _failed == 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ok    ", name)
	else:
		_failed += 1
		var msg := name if detail.is_empty() else "%s — %s" % [name, detail]
		_errors.append(msg)
		print("  FAIL  ", msg)


func _materials_cached() -> void:
	MaterialLibrary.ensure()
	MaterialLibrary.ensure()
	_ok("shared ivory", MaterialLibrary.ivory_mat != null)
	_ok("shared ebony", MaterialLibrary.ebony_mat != null)
	_ok("ivory identity", MaterialLibrary.piece_body(ChessTypes.WHITE) == MaterialLibrary.ivory_mat)
	_ok("ebony identity", MaterialLibrary.piece_body(ChessTypes.BLACK) == MaterialLibrary.ebony_mat)
	_ok("gold trim", MaterialLibrary.gold_trim_mat != null)
	_ok("legal marker", MaterialLibrary.legal_mat != null)


func _piece_meshes_cached() -> void:
	var a := PieceMeshBuilder.build(ChessTypes.QUEEN, ChessTypes.WHITE)
	var b := PieceMeshBuilder.build(ChessTypes.QUEEN, ChessTypes.WHITE)
	_ok("queen instances distinct", a != b)
	var ma := _first_mesh(a)
	var mb := _first_mesh(b)
	_ok("queen meshes shared", ma != null and ma == mb)
	_ok("collision present", _has_body(a) and _has_body(b))
	a.free()
	b.free()


func _first_mesh(node: Node) -> Mesh:
	for c in node.get_children():
		if c is MeshInstance3D:
			return (c as MeshInstance3D).mesh
		var nested := _first_mesh(c)
		if nested:
			return nested
	return null


func _has_body(node: Node) -> bool:
	for c in node.get_children():
		if c is StaticBody3D:
			return true
		if _has_body(c):
			return true
	return false
