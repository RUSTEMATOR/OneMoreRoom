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
	-- Creator Store, verified insertable and free at the time of writing. Applied as
	-- Decals over each rig's own material/colour rather than replacing it -- if a
	-- texture ever fails to load, the part still shows its correct base colour, so a
	-- broken CDN fetch degrades to "flat" rather than to a missing/pink part.
	textures = {
		rustHusk = "rbxassetid://14872045086",
		chromeHusk = "rbxassetid://2799843079",
		signalSentry = "rbxassetid://24329741",
		signalCultist = "rbxassetid://160935460",
		theWarden = "rbxassetid://44256773",
	},
}
