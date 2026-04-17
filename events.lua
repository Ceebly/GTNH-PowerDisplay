local event     = require('event')
local events    = {}
local exitFlag  = false

local glassesAdded = {}
local glassesRemoved = {}

function events.keyboardEvent(eventName, keyboardAddress, charNum, codeNum, playerName)
  -- Exit if 'c' was pressed
  if charNum == 99 then
    exitFlag = true
    return false -- Unregister this event listener
  end
end

function events.componentAdded(eventName, address, componentType)
  if componentType == 'glasses' then
    table.insert(glassesAdded, address)
  end
end

function events.componentRemoved(eventName, address, componentType)
  if componentType == 'glasses' then
    table.insert(glassesRemoved, address)
  end
end

function events.hookEvents()
  exitFlag = false
  glassesAdded = {}
  glassesRemoved = {}
  event.listen('key_up', events.keyboardEvent)
  event.listen('component_added', events.componentAdded)
  event.listen('component_removed', events.componentRemoved)
end

function events.unhookEvents()
  event.ignore('key_up', events.keyboardEvent)
  event.ignore('component_added', events.componentAdded)
  event.ignore('component_removed', events.componentRemoved)
end

function events.needExit()
  return exitFlag
end

function events.drainGlassesChanges()
  local added = glassesAdded
  local removed = glassesRemoved
  glassesAdded = {}
  glassesRemoved = {}
  return added, removed
end

return events
