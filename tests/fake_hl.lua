-- A small stand-in for Hyprland's Lua API: just enough of hl.* for
-- hypr/stage.lua, recording what it registers. Like Hyprland, it refuses a
-- second gesture with the same fingers and direction, and an unset of a
-- gesture that doesn't exist.
local fake = { gestures = {}, binds = {}, rules = {}, events = {} }

local function gesture_key(spec)
  return tostring(spec.fingers) .. ":" .. tostring(spec.direction) .. ":" .. tostring(spec.mods or "")
end

hl = {
  dsp = {
    event = function(message)
      assert(type(message) == "string", "hl.dsp.event takes a string")
      return { kind = "event", message = message }
    end,
  },
  dispatch = function(dispatcher)
    assert(type(dispatcher) == "table" and dispatcher.kind == "event", "only events are dispatched")
    fake.events[#fake.events + 1] = dispatcher.message
  end,
  gesture = function(spec)
    assert(type(spec) == "table", "hl.gesture takes a table")
    assert(type(spec.fingers) == "number" and spec.fingers >= 2 and spec.fingers <= 9, "fingers in 2-9")
    local key = gesture_key(spec)
    if spec.action == "unset" then
      if not fake.gestures[key] then error("no gesture to unset: " .. key) end
      fake.gestures[key] = nil
      return
    end
    if fake.gestures[key] then error("gesture already set: " .. key) end
    fake.gestures[key] = spec
  end,
  bind = function(keys, dispatcher, options)
    assert(type(keys) == "string")
    local handle = { keys = keys, dispatcher = dispatcher, options = options }
    function handle:remove() fake.binds[self] = nil end
    fake.binds[handle] = true
    return handle
  end,
  window_rule = function(spec)
    assert(type(spec.match) == "table", "window rules match something")
    local rule = { spec = spec, enabled = true, window = true }
    function rule:set_enabled(value) self.enabled = value end
    fake.rules[#fake.rules + 1] = rule
    return rule
  end,
  layer_rule = function(spec)
    local rule = { spec = spec, enabled = true }
    function rule:set_enabled(value) self.enabled = value end
    fake.rules[#fake.rules + 1] = rule
    return rule
  end,
}

function fake.active_binds()
  local out = {}
  for handle in pairs(fake.binds) do out[#out + 1] = handle end
  table.sort(out, function(a, b) return a.keys < b.keys end)
  return out
end

function fake.enabled_rules()
  local count = 0
  for _, rule in ipairs(fake.rules) do
    if rule.enabled then count = count + 1 end
  end
  return count
end

function fake.gesture(fingers, direction)
  return fake.gestures[tostring(fingers) .. ":" .. direction .. ":"]
end

return fake
