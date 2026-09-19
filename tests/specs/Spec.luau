--!strict
-- A result accumulator, not a framework. If specs pass ~15 files, swap this and RunAll
-- for TestEZ and set std = "roblox+testez" in selene.toml; nothing else changes.

export type Check = {
	desc: string,
	ok: boolean,
	detail: string?,
}

export type Result = {
	name: string,
	passed: boolean,
	checks: { Check },
}

local Spec = {}
Spec.__index = Spec

function Spec.new(name: string)
	return setmetatable({ name = name, checks = {} :: { Check } }, Spec)
end

function Spec:check(desc: string, ok: boolean, detail: any?)
	table.insert(self.checks, {
		desc = desc,
		ok = ok,
		detail = if detail ~= nil then tostring(detail) else nil,
	})
end

function Spec:equals(desc: string, actual: any, expected: any)
	self:check(desc, actual == expected, `got {tostring(actual)}, want {tostring(expected)}`)
end

function Spec:truthy(desc: string, value: any)
	self:check(desc, value and true or false, tostring(value))
end

function Spec:finish(): Result
	local passed = true
	for _, entry in self.checks do
		if not entry.ok then
			passed = false
		end
	end
	return { name = self.name, passed = passed, checks = self.checks }
end

return Spec
