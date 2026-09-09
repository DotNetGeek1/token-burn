class_name RoomProgression
extends RefCounted

## Which room the run is drawn in. The room is presentation and nothing else:
## it is derived from the Infrastructure Tier the player has bought, through
## the `room` each entry in `infrastructure.json` names, and no number in the
## game reads back from it. The art catalog, the cabinet shell and the
## investor's "new premises" call all ask here rather than at `build.dwelling`,
## so a room key can change without anything in `economy`, `compute`, `build`,
## `business` or `investor` noticing.

## The room the campaign starts in, and the one every unknown key draws as.
const DEFAULT_ROOM := "bedroom"
## The investor's trigger for arriving in a new room; variants are room ids.
const ROOM_CHANGED_TRIGGER := "room_changed"


## The room id for the run's infrastructure tier ("bedroom" … "moon_facility").
static func room_for(run_state: RunState, content_db: Node = null) -> String:
	if run_state == null:
		return DEFAULT_ROOM
	var room: String = InfrastructureSystem.room_id(run_state, content_db)
	return room if not room.is_empty() else DEFAULT_ROOM


## The room a given infrastructure tier is drawn in.
static func room_at(tier: int, content_db: Node = null) -> String:
	var room: String = InfrastructureSystem.room_id_at(tier, content_db)
	return room if not room.is_empty() else DEFAULT_ROOM


## "Office Unit", "Moon Facility": the room id in words.
static func room_name(room_id: String) -> String:
	return room_id.replace("_", " ").capitalize()


## The narrative key for the investor's line on arriving in the run's current
## room ("room_changed.garage"), as `infrastructure.json` authors it. Empty
## when the tier carries none.
static func investor_line(run_state: RunState, content_db: Node = null) -> String:
	if run_state == null:
		return ""
	return InfrastructureSystem.investor_line(run_state, content_db)


## The variant `InvestorVoice.call_for(ROOM_CHANGED_TRIGGER, variant)` wants
## for the run's room: the room id, read off the authored line key when there
## is one so the two cannot drift.
static func investor_variant(run_state: RunState, content_db: Node = null) -> String:
	var line: String = investor_line(run_state, content_db)
	var prefix: String = ROOM_CHANGED_TRIGGER + "."
	if line.begins_with(prefix):
		return line.substr(prefix.length())
	return room_for(run_state, content_db)
