--!strict
-- Deterministic RNG. Nothing in src/ may call math.random — the pre-commit hook rejects it.
-- Sub-streams are derived by key so adding a new consumer cannot shift an existing one's sequence.

local MODULUS = 2147483647

local Rng = {}
Rng.__index = Rng

local function deriveSeed(seed: number, parts: { any }): number
	local h = seed % MODULUS
	for _, part in parts do
		local text = tostring(part)
		for i = 1, #text do
			h = (h * 31 + text:byte(i)) % MODULUS
		end
	end
	return h
end

function Rng.new(seed: number, ...: any)
	local self = setmetatable({}, Rng)
	self._random = Random.new(deriveSeed(seed, { ... }))
	return self
end

function Rng:int(min: number, max: number): number
	return self._random:NextInteger(min, max)
end

function Rng:number(min: number?, max: number?): number
	if min ~= nil and max ~= nil then
		return self._random:NextNumber(min, max)
	end
	return self._random:NextNumber()
end

function Rng:pick(list: { any }): any
	return list[self._random:NextInteger(1, #list)]
end

function Rng:chance(probability: number): boolean
	return self._random:NextNumber() < probability
end

-- Fisher-Yates in place, so shuffles are reproducible too.
function Rng:shuffle(list: { any }): { any }
	for i = #list, 2, -1 do
		local j = self._random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

export type Rng = typeof(setmetatable({} :: { _random: Random }, Rng))

return Rng
