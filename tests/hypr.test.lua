-- Runs hypr/stage.lua against a fake Hyprland API.
-- Usage (from the plugin directory): lua tests/hypr.test.lua
package.path = "./tests/?.lua;" .. package.path
local fake = require("fake_hl")
local register = dofile("hypr/stage.lua")

local passed = 0
local function check(condition, message)
  if not condition then error("FAILED: " .. message, 2) end
  passed = passed + 1
end

local options = {
  fingers = 5,
  desktopSwipe = 4,
  binds = {
    { keys = "SUPER + A", event = "toggle", description = "Mission Control (Stage Control)" },
    { keys = "SUPER + ALT + A", event = "expose", description = "Application windows (Stage Control)" },
  },
}

-- First registration.
check(register(options) == "ok", "registers cleanly")
check(fake.gesture(5, "vertical") ~= nil, "five-finger vertical gesture")
check(fake.gesture(4, "horizontal") ~= nil, "four-finger desktop swipe")
check(fake.gesture(4, "horizontal").action == "workspace", "desktop swipe is Hyprland's workspace gesture")
check(#fake.active_binds() == 2, "two shortcuts")
check(fake.enabled_rules() == 2, "a layer rule and a window rule")
check(fake.rules[1].spec.no_anim == true, "layer rule turns off Hyprland's animation")
check(fake.rules[2].window and fake.rules[2].spec.float == true and fake.rules[2].spec.match.title == "^Stage Control$", "settings window floats")

-- Registering again replaces everything instead of stacking a second copy.
check(register(options) == "ok", "registers again without 'already set' errors")
check(#fake.active_binds() == 2, "still two shortcuts")
check(fake.enabled_rules() == 2, "still just the two rules enabled")

-- The gesture forwards every step as an event.
local spec = fake.gesture(5, "vertical")
fake.events = {}
spec.action.start({ delta = { x = 1.234, y = -5.678 }, time_ms = 1000, fingers = 5, type = "swipe" })
spec.action.update({ delta = { x = 0, y = -12.5 }, time_ms = 1016, fingers = 5, type = "swipe" })
spec.action.finish({ cancelled = false, time_ms = 1032, type = "swipe" })
check(fake.events[1] == "marcho78.stage-control|g|start|1.23|-5.68|1000.00|5", "start event: " .. tostring(fake.events[1]))
check(fake.events[2] == "marcho78.stage-control|g|update|0.00|-12.50|1016.00|5", "update event: " .. tostring(fake.events[2]))
check(fake.events[3] == "marcho78.stage-control|g|finish|0|1032.00", "finish event: " .. tostring(fake.events[3]))

-- Garbage from Hyprland can't break the message format.
fake.events = {}
spec.action.update(nil)
spec.action.update({ delta = { x = 0 / 0, y = math.huge }, time_ms = "x", fingers = 99 })
spec.action.finish({ cancelled = true })
check(fake.events[1] == "marcho78.stage-control|g|update|0.00|0.00|0.00|0", "nil event: " .. tostring(fake.events[1]))
check(fake.events[2] == "marcho78.stage-control|g|update|0.00|0.00|0.00|0", "nan/inf event: " .. tostring(fake.events[2]))
check(fake.events[3] == "marcho78.stage-control|g|finish|1|0.00", "cancelled finish: " .. tostring(fake.events[3]))

-- Shortcuts send their event.
local binds = fake.active_binds()
fake.events = {}
for _, bind in ipairs(binds) do hl.dispatch(bind.dispatcher) end
check(fake.events[1] == "marcho78.stage-control|toggle", "SUPER + A toggles Mission Control")
check(fake.events[2] == "marcho78.stage-control|expose", "SUPER + ALT + A opens App Exposé")
check(binds[1].options.description == "Mission Control (Stage Control)", "description kept")

-- Bad options are refused, one by one.
local status = register({
  fingers = 7,
  desktopSwipe = "4",
  binds = {
    { keys = "SUPER + A; os.execute('x')", event = "toggle" },
    { keys = "SUPER + B", event = "exec" },
    { keys = "SUPER + C", event = "toggle", description = "bad\nnewline" },
    "not a table",
  },
})
check(fake.gesture(5, "vertical") == nil, "old gesture removed")
check(fake.gesture(7, "vertical") == nil, "seven fingers refused")
check(fake.gesture(4, "horizontal") ~= nil, "numeric string for desktop swipe still accepted by tonumber")
check(#fake.active_binds() == 1, "only the valid shortcut registered")
check(fake.active_binds()[1].options.description == "Stage Control", "unsafe description replaced")
check(status:find("invalid keys", 1, true) ~= nil, "reports invalid keys")
check(status:find("unknown action", 1, true) ~= nil, "reports unknown action")
check(not status:find("\n", 1, true), "status is one line")

-- Turning everything off leaves nothing behind.
check(register({ fingers = 0, desktopSwipe = 0, binds = {} }) == "ok", "empty registration")
check(next(fake.gestures) == nil, "no gestures left")
check(#fake.active_binds() == 0, "no shortcuts left")
check(fake.enabled_rules() == 2, "only the two rules")

-- A gesture that is already taken (by the user's own config) is reported, not fatal.
hl.gesture({ fingers = 3, direction = "vertical", action = "workspace" })
status = register({ fingers = 3, desktopSwipe = 0, binds = {} })
check(status:find("3-finger swipe", 1, true) ~= nil, "reports the taken gesture")
check(fake.gesture(3, "vertical").action == "workspace", "the user's gesture is untouched")
check(register({ fingers = 0, desktopSwipe = 0, binds = {} }) == "ok", "cleanup doesn't unset the user's gesture")
check(fake.gesture(3, "vertical") ~= nil, "user's gesture still there")

print("hypr: " .. passed .. " checks passed")
