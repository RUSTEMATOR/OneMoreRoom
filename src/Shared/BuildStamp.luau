--!strict
-- Bumped at the start of every phase. The QA loop reads this module's Source out of the
-- live DataModel to prove the Rojo plugin is actually connected — `rojo serve` running is
-- not the same thing, and a stale Studio is the main way a session silently diverges.

return {
	id = "phase07-20260919",
}
