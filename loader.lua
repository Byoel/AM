-- AM loader. Upload as loader.lua beside AM.lua in Byoel/AM.
-- Keep the full automation script in AM.lua; do not replace it with this loader.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local BASE = "https://raw.githubusercontent.com/Byoel/AM/refs/heads/main/"
local SCRIPT_FILE = "AM.lua"

local env = (getgenv and getgenv()) or _G
if env.AMLoaderBusy then
    warn("[AM] The script is already loading.")
    return
end
env.AMLoaderBusy = true

local ok, err = pcall(function()
    local source = game:HttpGet(BASE .. SCRIPT_FILE)
    assert(type(source) == "string" and #source > 0, "The script download was empty.")

    local scriptFunction, compileError = loadstring(source, "@AM.lua")
    assert(scriptFunction, "Script could not compile: " .. tostring(compileError))
    scriptFunction()
end)

env.AMLoaderBusy = nil
if not ok then
    warn("[AM] Loader failed: " .. tostring(err))
end
