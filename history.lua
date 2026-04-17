local computer = require('computer')
local history = {}

local buffer = {}
local bufferSize = 0
local bufferHead = 0
local maxEntries = 8740
local lastSampleTime = 0

function history.init(sampleInterval)
  maxEntries = math.ceil(86400 / sampleInterval) + 100
end

function history.sample(euStored, sampleInterval)
  local now = computer.uptime()
  if now - lastSampleTime >= sampleInterval then
    bufferHead = (bufferHead % maxEntries) + 1
    buffer[bufferHead] = {time = now, value = euStored}
    if bufferSize < maxEntries then
      bufferSize = bufferSize + 1
    end
    lastSampleTime = now
  end
end

function history.getDelta(windowSeconds)
  if bufferSize == 0 then return nil end
  local now = buffer[bufferHead].time
  local currentValue = buffer[bufferHead].value
  local targetTime = now - windowSeconds

  local bestEntry = nil
  local bestDiff = math.huge
  for i = 1, bufferSize do
    local idx = ((bufferHead - i) % maxEntries) + 1
    local entry = buffer[idx]
    if entry then
      local diff = math.abs(entry.time - targetTime)
      if diff < bestDiff then
        bestDiff = diff
        bestEntry = entry
      end
      if entry.time < targetTime then
        break
      end
    end
  end

  if bestEntry == nil then return nil end
  if bestDiff > windowSeconds * 0.2 then return nil end
  return currentValue - bestEntry.value
end

function history.getDeltas(windows)
  local deltas = {}
  for i = 1, #windows do
    deltas[i] = history.getDelta(windows[i])
  end
  return deltas
end

return history
