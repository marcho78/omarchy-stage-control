-- Stage Control (marcho78.stage-control): the Hyprland half.
--
-- The service runs this inside Hyprland with `hyprctl eval` when the shell
-- starts, after every Hyprland config reload, and when the settings change:
--
--   return dofile("<plugin>/hypr/stage.lua")({ fingers = 4, desktopSwipe = 0, binds = { ... } })
--
-- It only registers input and two rules: a live trackpad gesture, keyboard
-- shortcuts, an optional desktop swipe, a layer rule for Stage Control's own
-- surfaces and a window rule that floats its settings window. The gesture and
-- the shortcuts send messages to the service over Hyprland's event socket
-- (hl.dsp.event); the desktop swipe is Hyprland's own workspace gesture.
-- Nothing here runs programs or reads or writes files. Your Hyprland config is
-- never edited: a config reload drops all of this, and the service registers
-- again.

local PREFIX = "marcho78.stage-control|"
local EVENTS = { toggle = true, expose = true, ["desktop-prev"] = true, ["desktop-next"] = true }
local STATE = "__marcho78_stage_control"

local function send(message)
  hl.dispatch(hl.dsp.event(PREFIX .. message))
end

local function number(value)
  value = tonumber(value) or 0
  if value ~= value or value == math.huge or value == -math.huge then value = 0 end
  return string.format("%.2f", value)
end

local function delta(event, axis)
  local d = type(event) == "table" and event.delta or nil
  return number(type(d) == "table" and d[axis] or 0)
end

local function whole(value, low, high)
  value = math.tointeger(tonumber(value) or 0) or 0
  if value < low or value > high then return 0 end
  return value
end

local function forward(phase, event)
  local time = number(type(event) == "table" and event.time_ms or 0)
  if phase == "finish" then
    local cancelled = type(event) == "table" and event.cancelled == true
    send("g|finish|" .. (cancelled and "1" or "0") .. "|" .. time)
  else
    local fingers = whole(type(event) == "table" and event.fingers or 0, 0, 9)
    send("g|" .. phase .. "|" .. delta(event, "x") .. "|" .. delta(event, "y") .. "|" .. time .. "|" .. fingers)
  end
end

-- Remove everything a previous run registered in this Lua state. A config
-- reload starts a fresh state, so this only matters for shell restarts and
-- settings changes.
local function undo(state)
  for _, bind in ipairs(state.binds or {}) do pcall(function() bind:remove() end) end
  for _, rule in ipairs(state.rules or {}) do pcall(function() rule:set_enabled(false) end) end
  for _, spec in ipairs(state.gestures or {}) do pcall(hl.gesture, spec) end
end

return function(options)
  options = type(options) == "table" and options or {}

  local previous = rawget(_G, STATE)
  if type(previous) == "table" then undo(previous) end
  local state = { binds = {}, rules = {}, gestures = {}, problems = {} }
  rawset(_G, STATE, state)

  local function problem(text)
    state.problems[#state.problems + 1] = tostring(text):gsub("[\r\n|;]", " ")
  end

  -- Stage Control animates its own surfaces, so skip Hyprland's layer fade for them.
  local ok, rule = pcall(hl.layer_rule, { match = { namespace = "^marcho78-stage-control" }, no_anim = true })
  if ok and rule then state.rules[#state.rules + 1] = rule else problem("layer rule: " .. tostring(rule)) end

  -- The settings window floats in the middle of the screen, like a macOS
  -- settings window, instead of tiling.
  local placed, window_rule = pcall(hl.window_rule, {
    match = { class = "^org\\.quickshell$", title = "^Stage Control$" },
    float = true,
    center = true,
    size = { 860, 680 },
  })
  if placed and window_rule then state.rules[#state.rules + 1] = window_rule else problem("window rule: " .. tostring(window_rule)) end

  -- Mission Control follows the fingers: every step of a vertical swipe goes to
  -- the service, which decides between Mission Control and App Exposé.
  local fingers = whole(options.fingers, 3, 5)
  if fingers > 0 then
    local spec = {
      fingers = fingers,
      direction = "vertical",
      action = {
        start = function(event) forward("start", event) end,
        update = function(event) forward("update", event) end,
        finish = function(event) forward("finish", event) end,
      },
    }
    local registered, err = pcall(hl.gesture, spec)
    if registered then
      state.gestures[#state.gestures + 1] = { fingers = fingers, direction = "vertical", action = "unset" }
    else
      problem(fingers .. "-finger swipe: " .. tostring(err))
    end
  end

  -- Swiping between desktops is Hyprland's own workspace gesture.
  local swipe = whole(options.desktopSwipe, 3, 5)
  if swipe > 0 then
    local registered, err = pcall(hl.gesture, { fingers = swipe, direction = "horizontal", action = "workspace" })
    if registered then
      state.gestures[#state.gestures + 1] = { fingers = swipe, direction = "horizontal", action = "unset" }
    else
      problem(swipe .. "-finger desktop swipe: " .. tostring(err))
    end
  end

  for _, bind in ipairs(type(options.binds) == "table" and options.binds or {}) do
    local keys = type(bind) == "table" and bind.keys or nil
    local event = type(bind) == "table" and bind.event or nil
    local description = type(bind) == "table" and bind.description or ""
    if type(keys) ~= "string" or #keys > 64 or not keys:match("^[%w_ %+]+$") then
      problem("skipped a shortcut with invalid keys")
    elseif not EVENTS[event] then
      problem("skipped " .. keys .. ": unknown action")
    else
      if type(description) ~= "string" or #description > 80 or not description:match("^[%w%p ]*$") then
        description = "Stage Control"
      end
      local done, handle = pcall(hl.bind, keys, hl.dsp.event(PREFIX .. event), { description = description })
      if done and handle then
        state.binds[#state.binds + 1] = handle
      else
        problem(keys .. ": " .. tostring(handle))
      end
    end
  end

  if #state.problems == 0 then return "ok" end
  return "ok|" .. table.concat(state.problems, ";")
end
