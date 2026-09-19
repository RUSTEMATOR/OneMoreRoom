--!strict
-- Phase 5 acceptance: room types are data entries, not new plumbing.
--
-- The real assertion here is structural — every template goes through the same
-- RoomService with no per-type branching, and a room with an empty encounter clears
-- itself. If adding a type ever requires touching RoomService, this spec's premise
-- has been broken even if every check still passes.
--
-- Shop and Event are deliberately absent: a shop needs Phase 7 loot to spend and
-- Phase 12 UI to choose with, and faking either is worse than not having them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Spec = require(script.Parent.Spec)

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local FloorConfig = require(ReplicatedStorage.Shared.FloorConfig)
local RoomConfig = require(ReplicatedStorage.Shared.RoomConfig)
local EnemyService = require(ServerScriptService.Services.EnemyService)
local FloorService = require(ServerScriptService.Services.FloorService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local RoomService = require(ServerScriptService.Services.RoomService)
local RunSessionService = require(ServerScriptService.Services.RunSessionService)

local EXPECTED_TEMPLATES = { "Combat", "Elite", "Treasure", "Healing" }

-- Put the room's centre on the player, so the prize is within pickup range without
-- moving a client-owned character.
local function moveRoomOnto(room: RoomService.Room, position: Vector3)
	room.model:PivotTo(CFrame.new(position - Vector3.new(0, 3, 0)))
end

return function()
	local spec = Spec.new("Phase05_RoomTypes")

	-- ------------------------------------------------- A. every template

	for _, id in EXPECTED_TEMPLATES do
		local template = RoomConfig.templates[id]
		spec:truthy(`template {id} exists`, template)
		if template == nil then
			continue
		end
		-- The same required shape for every type is what lets RoomService stay
		-- generic. A missing key here means a new type needed special handling.
		spec:check(`{id} has an interior`, template.interior ~= nil and template.interior.X > 0)
		spec:check(`{id} has a doorway`, template.doorway ~= nil and template.doorway.width > 0)
		spec:truthy(`{id} declares enemySpawns`, template.enemySpawns ~= nil)
		spec:check(
			`{id} door travel clears its doorway`,
			template.doorTravel >= template.doorway.height
		)
		spec:check(`{id} has door timing`, template.doorTime > 0 and template.sealDelay >= 0)
	end

	-- Shop and Event must stay absent until they can be real.
	spec:truthy("Shop is not yet a template", RoomConfig.templates.Shop == nil)
	spec:truthy("Event is not yet a template", RoomConfig.templates.Event == nil)

	-- -------------------------------------------------------- B. the Elite

	local elite = EnemyConfig.kinds.SkeletonElite
	local basic = EnemyConfig.kinds.Skeleton
	spec:truthy("elite enemy exists", elite)
	if elite ~= nil then
		spec:check("elite has more health", elite.maxHealth > basic.maxHealth, elite.maxHealth)
		spec:check("elite hits harder", elite.damage > basic.damage, elite.damage)
		spec:check("elite pays out more", elite.goldReward > basic.goldReward, elite.goldReward)
		-- An elite that cannot be dodged is not harder, it is unfair.
		spec:check(
			"elite telegraph still outlasts the dodge i-frame window",
			elite.attackWindup > CombatConfig.dodge.iframes,
			`{elite.attackWindup} vs {CombatConfig.dodge.iframes}`
		)
		spec:check(
			"elite is still slower than the player",
			elite.walkSpeed < CombatConfig.player.walkSpeed,
			`{elite.walkSpeed} vs {CombatConfig.player.walkSpeed}`
		)
	end
	spec:equals(
		"the Elite room uses the elite enemy",
		RoomConfig.templates.Elite.enemyKind,
		"SkeletonElite"
	)

	-- ------------------------------------------------- C. reward templates

	spec:equals("Treasure has no encounter", #RoomConfig.templates.Treasure.enemySpawns, 0)
	spec:equals("Healing has no encounter", #RoomConfig.templates.Healing.enemySpawns, 0)
	spec:equals("Treasure pays gold", RoomConfig.templates.Treasure.reward.kind, "gold")
	spec:equals("Healing restores health", RoomConfig.templates.Healing.reward.kind, "heal")
	spec:check(
		"the heal is a fraction, so it survives a max-health upgrade",
		RoomConfig.templates.Healing.reward.amount > 0
			and RoomConfig.templates.Healing.reward.amount <= 1,
		RoomConfig.templates.Healing.reward.amount
	)
	spec:truthy("Combat has no prize", RoomConfig.templates.Combat.reward == nil)

	-- ------------------------------------------------------ D. the sequence

	local seen: { [string]: boolean } = {}
	for depth = 1, #FloorConfig.sequence do
		local template = FloorConfig.templateForFloor(depth)
		seen[template] = true
		spec:truthy(`floor {depth} maps to a real template`, RoomConfig.templates[template] ~= nil)
	end
	spec:truthy("the rotation includes a Treasure room", seen.Treasure)
	spec:truthy("the rotation includes an Elite room", seen.Elite)
	spec:truthy("the rotation includes a Healing room", seen.Healing)

	-- ------------------------------------------------ player-driven checks

	local player = Players:GetPlayers()[1]
	if player == nil or not PlayerService.isActionable(player) then
		spec:check("a live player is present", false, "run in Play mode")
		return spec:finish()
	end

	local generated = FloorService.generatedFolder()
	local made: { RoomService.Room } = {}

	local ok, err = pcall(function()
		local root = (PlayerService.get(player) :: any).rootPart :: BasePart

		-- ---------------------------------- E. every type builds and clears

		for _, id in EXPECTED_TEMPLATES do
			local room = RoomService.create(id, CFrame.new(3000, 5, 3000 + #made * 200), generated)
			spec:truthy(`{id} builds`, room)
			if room ~= nil then
				table.insert(made, room)
				spec:truthy(`{id} has a floor`, room.floor)
				spec:truthy(`{id} has both doors`, room.entranceDoor and room.exitDoor)
				local wantsPrize = RoomConfig.templates[id].reward ~= nil
				spec:equals(
					`{id} prize presence matches its template`,
					room.prize ~= nil,
					wantsPrize
				)
			end
		end

		for _, room in made do
			RoomService.destroy(room)
		end
		table.clear(made)

		-- ------------------------------ F. a reward room clears itself and pays

		-- The run has to start BEFORE the room lands on the player: the prize is
		-- picked up on contact, and gold awarded outside an active run is worth
		-- nothing by design.
		RunSessionService.begin(777)
		local goldBefore = (RunSessionService.get() :: any).gold

		local treasure = RoomService.create("Treasure", CFrame.new(3000, 5, 3000), generated)
		if treasure ~= nil then
			table.insert(made, treasure)
			moveRoomOnto(treasure, root.Position)

			local t = RoomConfig.templates.Treasure
			task.wait(t.sealDelay + t.clearDelay + t.doorTime + 0.8)

			-- A reward room has nothing to fight, so it must clear itself rather
			-- than sealing the player in forever.
			spec:equals("a room with no encounter clears itself", treasure.phase, "Cleared")
			spec:check("its exit opened", RoomService.isDoorOpen(treasure, treasure.exitDoor))

			spec:truthy("the treasure prize was taken on contact", treasure.prizeTaken)
			spec:check(
				"the prize paid its gold into the run",
				(RunSessionService.get() :: any).gold
					>= goldBefore + RoomConfig.templates.Treasure.reward.amount,
				`{goldBefore} -> {(RunSessionService.get() :: any).gold}`
			)
			spec:truthy("the prize was consumed", treasure.prize == nil)

			RoomService.destroy(treasure)
			table.clear(made)
		end

		-- ---------------------------------------------- G. the healing prize

		PlayerService.setHealth(player, 20)
		local healRoom = RoomService.create("Healing", CFrame.new(3400, 5, 3400), generated)
		if healRoom ~= nil then
			table.insert(made, healRoom)
			moveRoomOnto(healRoom, root.Position)
			task.wait(0.9)

			local healed = PlayerService.get(player)
			if healed ~= nil then
				spec:check(
					"the healing prize restored health",
					healed.health > 20,
					`20 -> {healed.health}`
				)
				spec:check(
					"healing never exceeds the maximum",
					healed.health <= healed.maxHealth,
					healed.health
				)
			end
			spec:truthy("the healing prize was consumed", healRoom.prizeTaken)
		end

		RunSessionService.finish()
	end)

	if not ok then
		spec:check("room type checks completed without error", false, err)
	end

	-- ------------------------------------------------------- H. teardown

	for _, room in made do
		RoomService.destroy(room)
	end
	FloorService.endRun()
	EnemyService.despawnAll()
	PlayerService.setHealth(player, 100)
	PlayerService.setStamina(player, 100)

	spec:equals("teardown left Generated empty", #generated:GetChildren(), 0)

	return spec:finish()
end
