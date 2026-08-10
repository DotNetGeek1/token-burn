class_name ResolveMode
extends RefCounted

## Distinguishes a real action from a look-ahead. A preview clones the run
## state before resolving anything, so nothing here ever risks the run itself —
## this only controls whether resolution is allowed to broadcast on EventBus.
## Achievements, statistics and anything else listening globally must never
## react to a batch that only existed to answer "what would BURN TOKENS do?".

const PREVIEW := 0
const COMMIT := 1
