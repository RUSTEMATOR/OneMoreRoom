--!strict
-- Thin transport for the TypeSafe System One API. Knows how to send a request and
-- interpret a reply; knows nothing about runs, telemetry or the game.
--
-- THIS YIELDS. HttpService:RequestAsync blocks the calling thread for ~615ms in the
-- measured case, and longer on a retry. It must only ever be called from inside a
-- task.spawn, never from a Heartbeat step or from any service's Init or Start — the
-- same rule that keeps FloorService.loadFloor safe.
--
-- The transport is injectable so specs can exercise the whole path — payload shape,
-- retries, confidence gating — without a network or an API key.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReviewConfig = require(ReplicatedStorage.Shared.ReviewConfig)

local TypeSafeClient = {}

export type Response = {
	ok: boolean,
	-- "http" for a real status, or one of: disabled, nosecret, transport, decode, badstatus
	failure: string?,
	statusCode: number?,
	answers: { [string]: any }?,
	attempts: number,
	elapsed: number,
}

-- Swap this in a spec to run offline. Returns (ok, statusCode, body).
export type Transport = (
	url: string,
	headers: { [string]: any },
	body: string
) -> (boolean, number, string)

local function defaultTransport(
	url: string,
	headers: { [string]: any },
	body: string
): (boolean, number, string)
	local ok, result = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = headers,
			Body = body,
		})
	end)

	if not ok then
		-- Most commonly "HTTP requests are not enabled", which is a place setting
		-- rather than a fault, so it is reported rather than retried.
		return false, 0, tostring(result)
	end
	return true, result.StatusCode, result.Body
end

local transport: Transport = defaultTransport

function TypeSafeClient.setTransport(next: Transport?)
	transport = next or defaultTransport
end

-- Built fresh per request. A Secret cannot be logged or concatenated by accident,
-- which is the point of using one instead of a string.
local function authHeader(): any?
	local ok, secret = pcall(function()
		return HttpService:GetSecret(ReviewConfig.secretKey):AddPrefix("Bearer ")
	end)
	if not ok then
		return nil
	end
	return secret
end

function TypeSafeClient.ask(state: any, questions: { [string]: any }): Response
	local started = os.clock()

	if not ReviewConfig.enabled then
		return { ok = false, failure = "disabled", attempts = 0, elapsed = 0 }
	end

	-- The auth header exists only to satisfy the real endpoint. An injected transport
	-- is by definition not the real endpoint, so requiring a secret there would make
	-- the whole path untestable without one.
	local auth: any = "injected"
	if transport == defaultTransport then
		auth = authHeader()
		if auth == nil then
			-- No secret configured. Not worth retrying, and not worth a log line on
			-- every single run.
			return {
				ok = false,
				failure = "nosecret",
				attempts = 0,
				elapsed = os.clock() - started,
			}
		end
	end

	local body = HttpService:JSONEncode({
		model = ReviewConfig.model,
		state = state,
		questions = questions,
	})

	local headers = {
		["Authorization"] = auth,
		["Content-Type"] = "application/json",
	}

	local attempts = 0
	local lastStatus: number? = nil

	while attempts < ReviewConfig.request.maxAttempts do
		attempts += 1
		local sent, status, payload = transport(ReviewConfig.endpoint, headers, body)

		if not sent then
			return {
				ok = false,
				failure = "transport",
				attempts = attempts,
				elapsed = os.clock() - started,
			}
		end

		lastStatus = status

		if status == 200 then
			local decoded, value = pcall(function()
				return HttpService:JSONDecode(payload)
			end)
			if not decoded or typeof(value) ~= "table" or value.answers == nil then
				return {
					ok = false,
					failure = "decode",
					statusCode = status,
					attempts = attempts,
					elapsed = os.clock() - started,
				}
			end
			return {
				ok = true,
				statusCode = status,
				answers = value.answers,
				attempts = attempts,
				elapsed = os.clock() - started,
			}
		end

		if not ReviewConfig.request.retryableStatuses[status] then
			break
		end

		-- Exponential backoff, as the docs prescribe for 429 and 529. Yielding here
		-- is safe precisely because this whole call already runs off the tick.
		if attempts < ReviewConfig.request.maxAttempts then
			task.wait(ReviewConfig.request.backoffBaseSeconds * attempts)
		end
	end

	return {
		ok = false,
		failure = "badstatus",
		statusCode = lastStatus,
		attempts = attempts,
		elapsed = os.clock() - started,
	}
end

return TypeSafeClient
