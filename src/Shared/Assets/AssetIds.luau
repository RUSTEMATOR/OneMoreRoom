--!strict
-- Imported Roblox cloud assets, referenced by id. The manifest is text and diffable;
-- the asset itself lives on Roblox's CDN, so no binaries enter the repo.
--
-- An empty string means "play nothing". The sound helper returns early on one, so a
-- missing asset degrades silently instead of erroring a purely cosmetic path — which
-- the QA loop would otherwise score as a phase failure.

return {
	sounds = {
		swordSwing = "rbxassetid://5789211405",
		swordImpact = "rbxassetid://86702705197960",
		playerHurt = "",
		playerDeath = "",
		-- Creator Store, verified insertable and free at the time of writing.
		sentryBoltFire = "rbxassetid://135695524548843",
		sentryBoltImpact = "rbxassetid://201858087",
		cultistDetonation = "rbxassetid://129848017786439",
	},
}
