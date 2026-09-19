--!strict
-- Owns per-player runtime state. Keyed by player and plural from day one so Phase 14
-- co-op tunes scaling rather than rearchitecting single-player assumptions.

local Players = game:GetService("Players")

local PlayerService = {}

export type PlayerState = {
	player: Player,
	health: number,
	maxHealth: number,
	stamina: number,
	maxStamina: number,
}

local states: { [Player]: PlayerState } = {}

local function onPlayerAdded(player: Player)
	states[player] = {
		player = player,
		health = 100,
		maxHealth = 100,
		stamina = 100,
		maxStamina = 100,
	}
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
end

function PlayerService.Init()
	table.clear(states)
end

function PlayerService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function PlayerService.get(player: Player): PlayerState?
	return states[player]
end

function PlayerService.all(): { PlayerState }
	local list = {}
	for _, state in states do
		table.insert(list, state)
	end
	return list
end

return PlayerService
