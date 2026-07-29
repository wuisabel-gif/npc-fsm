class_name TargetActor
extends Node2D

@export var alive := true
@export var health := 100.0

func take_damage(amount: float) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		alive = false
