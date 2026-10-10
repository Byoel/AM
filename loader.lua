-- Upload this file as loader.lua. Keep the full HUB in AM.lua.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local supportedPlaces = {
    [117949143041402] = true, -- Anime Mysterious lobby
    [107610426295102] = true, -- Anime Mysterious match
}

if not supportedPlaces[game.PlaceId] then
    print("[Deggy HUB] Game not supported")
    return
end

local BASE = "https://raw.githubusercontent.com/Byoel/AM/refs/heads/main/"
local SCRIPT_FILE = "AM.lua"
local env = (getgenv and getgenv()) or _G
if env.AMLoaderBusy then
    warn("[Deggy HUB] The script is already loading.")
    return
end
env.AMLoaderBusy = true

local ok, err = pcall(function()
    local source = game:HttpGet(BASE .. SCRIPT_FILE, true)
    assert(type(source) == "string" and #source > 0, "The script download was empty.")
    local scriptFunction, compileError = loadstring(source, "@AM.lua")
    assert(scriptFunction, "Script could not compile: " .. tostring(compileError))
    scriptFunction()
end)

env.AMLoaderBusy = nil
if not ok then
    warn("[Deggy HUB] Loader failed: " .. tostring(err))
end
