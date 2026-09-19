--!strict
-- Server-authoritative from the first swing. Clients send intent via RequestAttack;
-- they never report outcomes. Phase 17 audits this, it does not retrofit it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local CombatService = {}

local requestAttack: RemoteEvent

function CombatService.Init()
	requestAttack = Net.event("RequestAttack")
end

function CombatService.Start()
	requestAttack.OnServerEvent:Connect(function(_player: Player)
		-- Phase 1 validates cooldown, stamina and range here, then applies damage.
	end)
end

return CombatService
