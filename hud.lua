local graphics  = require('graphics')
local config    = require('config')
local events    = require('events')
local history   = require('history')
local component = require('component')
local term      = require('term')
local lsc       = component.gt_machine
local glasses   = {}

-- Initialization
term.clear()
graphics.fox()
history.init(config.historySampleInterval)

local function setupGlasses(address)
  local ok, proxy = pcall(component.proxy, component.get(address))
  if not ok or not proxy then return nil end

  local okp, p1, p2, p3, p4 = pcall(proxy.getBindPlayers)
  local players = {}
  if okp then
    for _, v in ipairs({p1, p2, p3, p4}) do
      if type(v) == 'string' then table.insert(players, v) end
    end
  end

  local cfg = config.resolve(players)
  local entry = {
    proxy = proxy,
    address = address,
    players = players,
    cfg = cfg,
    lastPercent = 0,
  }

  local l  = cfg.length
  local h  = cfg.height
  local b1 = cfg.borderBottom
  local b2 = cfg.borderTop
  local y  = cfg.resolution[2] / cfg.GUIscale

  if not cfg.fullscreen then
    y = y - graphics.calcOffset(cfg.GUIscale)
  end

  entry.y, entry.l, entry.h, entry.b1, entry.b2 = y, l, h, b1, b2

  local okDraw = pcall(function()
    proxy.removeAll()

    -- Draw Static Shapes
    graphics.quad(proxy, {0, y-b1}, {3.5*h+l+b2+1, y-b1}, {2.5*h+l+1, y-b1-h-b2}, {0, y-b1-h-b2}, cfg.borderColor, cfg)
    graphics.quad(proxy, {0, y}, {3.5*h+l+b2+1, y}, {3.5*h+l+b2+1, y-b1}, {0, y-b1}, cfg.borderColor, cfg)
    graphics.quad(proxy, {3.5*h, y-b1}, {3.5*h+l, y-b1}, {2.5*h+l, y-b1-h}, {2.5*h, y-b1-h}, cfg.secondaryColor, cfg)

    -- Draw Energy Bar
    entry.energyBar = graphics.quad(proxy, {b2+3.25*h, y-b1}, {b2+3.25*h, y-b1}, {b2+2.25*h, y-b1-h}, {b2+2.25*h, y-b1-h}, cfg.primaryColor, cfg)
    entry.textPercent = graphics.text(proxy, 'X.X%', {0.5*h, y-b1-h/1.8-cfg.fontSize}, cfg.fontSize, cfg.primaryColor, cfg)

    -- Draw Optional Values
    entry.textCurr = graphics.text(proxy, '', {b2+3.25*h+1, y-b1-h/2-cfg.fontSize}, cfg.fontSize/1.3, cfg.textColor, cfg)
    entry.textMax = graphics.text(proxy, '', {-2.25*h+l, y-b1-h/2-cfg.fontSize}, cfg.fontSize/1.3, cfg.textColor, cfg)

    -- History Panel
    if cfg.showHistory then
      entry.historyPanel = graphics.drawHistoryPanel(proxy, cfg, y, l, h, b1, b2)
      local maintenanceY = entry.historyPanel.panelTop - cfg.historyBorderWidth - 3*cfg.fontSize
      entry.textMaintenance = graphics.text(proxy, '', {b2, maintenanceY}, cfg.fontSize, cfg.issueColor, cfg)
    else
      entry.textMaintenance = graphics.text(proxy, '', {b2, y-b1-b2-h-3*cfg.fontSize}, cfg.fontSize, cfg.issueColor, cfg)
    end
  end)

  if not okDraw then return nil end
  return entry
end

local function removeGlassesByAddress(address)
  for i = #glasses, 1, -1 do
    if glasses[i].address == address then
      table.remove(glasses, i)
    end
  end
end

-- Stand Ready for Exit + Component Hot-Plug Events
events.hookEvents()

-- Initial discovery
for address in component.list('glasses') do
  local entry = setupGlasses(address)
  if entry then table.insert(glasses, entry) end
end

-- ===== MAIN LOOP =====
while true do

  -- Process glasses connect/disconnect events
  local added, removed = events.drainGlassesChanges()
  for _, address in ipairs(removed) do
    removeGlassesByAddress(address)
  end
  for _, address in ipairs(added) do
    removeGlassesByAddress(address) -- avoid duplicates
    local entry = setupGlasses(address)
    if entry then table.insert(glasses, entry) end
  end

  -- Retrieve LSC data
  scan = lsc.getSensorInformation()

  if config.wirelessMode then
    power = scan[23]:gsub('%D', '')
    power = tonumber(power)
    capacity = config.wirelessMax
  else
    power = lsc.getEUStored()
    capacity = lsc.getEUMaxStored()
  end

  local percentage = math.min(power / capacity, 1)

  -- Sample history
  history.sample(power, config.historySampleInterval)

  for i = #glasses, 1, -1 do
    local entry = glasses[i]
    local ok = pcall(function()
      local cfg = entry.cfg
      local g   = entry.proxy
      local y   = entry.y
      local l   = entry.l
      local h   = entry.h
      local b1  = entry.b1
      local b2  = entry.b2

      -- Adjust Values
      local curr = ''
      if cfg.showCurrentEU then
        if cfg.metric then
          curr = graphics.metricParser(power)
        else
          curr = graphics.scientificParser(power)
        end
      end

      local rate = ''
      if cfg.showRate then
        rate = graphics.calcRate(percentage, entry.lastPercent, cfg.rateThreshold)
        entry.lastPercent = percentage
      end

      -- Adjust Energy Bar
      entry.energyBar.setVertex(2, b2+3.25*h+l*percentage, y-b1)
      entry.energyBar.setVertex(3, b2+2.25*h+l*percentage, y-b1-h)

      if percentage > 0.999 then
        entry.textPercent.setText('100%')
        entry.textPercent.setPosition(b2+2.1*h-2*cfg.fontSize*(#entry.textPercent.getText()), y-b1-h/1.8-cfg.fontSize)
      else
        entry.textPercent.setText(string.format('%.1f%%', percentage*100))
        entry.textPercent.setPosition(b2+2*h-2*cfg.fontSize*(#entry.textPercent.getText()-1), y-b1-h/1.8-cfg.fontSize)
      end

      entry.textCurr.setText(curr .. ' ' .. rate)

      if cfg.showMaxEU then
        local maxText
        if cfg.metric then
          maxText = graphics.metricParser(capacity)
        else
          maxText = graphics.scientificParser(capacity)
        end
        entry.textMax.setText(maxText)
        entry.textMax.setPosition(2.25*h+l-1.5*cfg.fontSize*(#entry.textMax.getText()-1), y-b1-h/2-cfg.fontSize)
      end

      -- Detect Maintenance Issues
      if #scan[17] < 43 then
        entry.textMaintenance.setText('Has Problems!')
      else
        entry.textMaintenance.setText('')
      end

      -- Update History Panel
      if cfg.showHistory and entry.historyPanel then
        local windows = cfg.historyWindows
        local deltas = history.getDeltas(windows)
        local panel = entry.historyPanel

        for w = 1, math.min(#deltas, #cfg.historyLabels) do
          -- Update delta + percentage text
          if panel.deltaTexts[w] then
            local deltaText = ''
            if cfg.showHistoryDelta then
              deltaText = graphics.formatDelta(deltas[w], cfg.metric)
            end
            if cfg.showHistoryPercent and deltas[w] ~= nil then
              local pct = string.format('%.1f%%', deltas[w] / capacity * 100)
              if deltas[w] > 0 then pct = '+' .. pct end
              if deltaText ~= '' then
                deltaText = deltaText .. ' (' .. pct .. ')'
              else
                deltaText = pct
              end
            elseif cfg.showHistoryPercent then
              if deltaText == '' then deltaText = 'N/A' end
            end
            panel.deltaTexts[w].setText(deltaText)
            if deltas[w] == nil then
              panel.deltaTexts[w].setColor(graphics.RGB(cfg.textColor))
            elseif deltas[w] >= 0 then
              panel.deltaTexts[w].setColor(graphics.RGB(cfg.primaryColor))
            else
              panel.deltaTexts[w].setColor(graphics.RGB(cfg.issueColor))
            end
          end

          -- Update rate text (EU/t)
          if cfg.showHistoryRate and panel.rateTexts[w] then
            local rateText = graphics.formatRate(deltas[w], windows[w], cfg.metric)
            panel.rateTexts[w].setText(rateText)
            if deltas[w] == nil then
              panel.rateTexts[w].setColor(graphics.RGB(cfg.textColor))
            elseif deltas[w] >= 0 then
              panel.rateTexts[w].setColor(graphics.RGB(cfg.primaryColor))
            else
              panel.rateTexts[w].setColor(graphics.RGB(cfg.issueColor))
            end
          end
        end
      end
    end)

    if not ok then
      -- Proxy is dead but no removal event has fired yet; drop this entry.
      -- It will be re-added if/when component_added fires.
      table.remove(glasses, i)
    end
  end

  -- Terminal Condition
  if events.needExit() then
    break
  end

  -- Pause
  os.sleep(config.sleep)
end

events.unhookEvents()
for i = 1, #glasses do
  pcall(function() glasses[i].proxy.removeAll() end)
end
