extends RefCounted
class_name MonsterProfile


## Issue 542. What a monster IS, and how much of one each monster is.
##
## A row reads "a Brute is 3.2x baseline hp at 0.45x speed" instead of "320".
## Radius is deliberately NOT here: it is collision geometry, not a stat, and
## the player's list of base stats does not include it.

const BASE_HP := 100
const BASE_DAMAGE := 10

## Powers of two on purpose. Scaling a float by one is exact, so every
## multiplier below reproduces the hand-written number it replaced bit for bit
## rather than one ULP away from it.
const BASE_MOVE_SPEED := 4.0
const BASE_RESISTANCE := 0.25

## 1.0 is "acts at the speed its actions are authored at". Above 1.0 is faster.
const BASE_ACTION_SPEED := 1.0

static func hp(multiplier: float) -> int:
	return int(round(float(BASE_HP) * multiplier))

static func damage(multiplier: float) -> int:
	return int(round(float(BASE_DAMAGE) * multiplier))

static func move_speed(multiplier: float) -> float:
	return BASE_MOVE_SPEED * multiplier

static func resistance(multiplier: float) -> float:
	return BASE_RESISTANCE * multiplier

## Issue 542. The enemy half of `PawnData.scale_action_ticks`, clamped at both
## ends: the fast end mirrors the pawn's -50% floor, the slow end stops a small
## multiplier turning a wind-up into a stall nobody can read.
const MIN_ENEMY_TICK_SCALE := 0.5
const MAX_ENEMY_TICK_SCALE := 2.0

static func scale_action_ticks(base_ticks: int, action_speed: float) -> int:
	if base_ticks <= 0:
		return base_ticks
	if action_speed <= 0.0:
		return base_ticks
	var scale := clampf(1.0 / action_speed, MIN_ENEMY_TICK_SCALE, MAX_ENEMY_TICK_SCALE)
	return maxi(1, int(round(float(base_ticks) * scale)))
