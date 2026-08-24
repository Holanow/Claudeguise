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
