extends RefCounted
class_name RoomScale

## Issue 814: floor 1's rooms were authored against a five-pawn party and are
## played by four, so the authored difficulty is aimed at a party that is not
## there. This derives the count from the party actually present.

## The party size the rooms were authored for. Four of ten rooms hold ten
## enemies, and those counts were never revisited when the party became four.
const AUTHORED_PARTY_SIZE := 5

## What a room holds when it is one of the outliers this floor over-authored.
const OUTLIER_COUNT := 10

## OFF is the shipped floor. EVERY_ROOM scales every room by the party's share
## of `AUTHORED_PARTY_SIZE`; OUTLIER_ROOMS applies the same factor to the
## ten-enemy rooms alone and leaves the rest authored. One factor across both,
## so neither arm is a number chosen to move a win rate.
enum Mode { OFF, EVERY_ROOM, OUTLIER_ROOMS }

static var MODE := Mode.OFF

## A copy, never the argument: `RoomLibrary._rooms` is a cache and `get_room`
## hands out the entry itself, so a trim in place would follow every later
## fight in the process.
##
## The kept indices are `(j * n) / keep`, which is an order-preserving even
## subsample rather than a cut from the end. It keeps index 0 -- the Rat King
## and The Warden are each first in their own room's spawn list -- and it takes
## the loss out of the whole mix instead of out of whatever was authored last.
static func scaled(room: RoomData, party_size: int) -> RoomData:
	if room == null or MODE == Mode.OFF:
		return room
	var n := room.enemy_spawns.size()
	if MODE == Mode.OUTLIER_ROOMS and n < OUTLIER_COUNT:
		return room
	var keep := maxi(1, int(round(float(n) * party_size / AUTHORED_PARTY_SIZE)))
	if keep >= n:
		return room
	var out := RoomData.new()
	out.id = room.id
	out.display_name = room.display_name
	out.pickable = room.pickable
	out.cells = room.cells
	out.party_spawns = room.party_spawns
	for j in keep:
		out.enemy_spawns.append(room.enemy_spawns[(j * n) / keep])
	return out

## What a room holds once scaled, without building the copy. The screens that
## tell the player how big a fight is read this, so the number they are shown
## is the number they get.
static func count_for(room: RoomData, party_size: int) -> int:
	return 0 if room == null else scaled(room, party_size).enemy_spawns.size()
