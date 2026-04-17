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

local function getCurrentPlayers(proxy)
  local ok, p1, p2, p3, p4, p5, p6 = pcall(proxy.getBindPlayers)
  local players = {}
  if ok then
    for _, v in ipairs({p1, p2, p3, p4, p5, p6}) do
      if type(v) == 'string' then table.insert(players, v) end
    end
  end
  return players
end

local function playersChanged(a, b)
  if #a ~= #b then return true end
  for i = 1, #a do
    if a[i] ~= b[i] then return true end
  end
  return false
end

local function computeLayout(cfg)
  local l  = cfg.length
  local h  = cfg.height
  local b1 = cfg.borderBottom
  local b2 = cfg.borderTop
  local y  = cfg.resolution[2] / cfg.GUIscale
  if not cfg.fullscreen then
    y = y - graphics.calcOffset(cfg.GUIscale)
  end
  return l, h, b1, b2, y
end

-- (Re)draw all static widgets on an entry's terminal and refresh widget references.
-- Returns true on success, false if the proxy errored (likely dead terminal).
local function drawWidgets(entry)
  local cfg = entry.cfg
  local g   = entry.proxy
  local l, h, b1, b2, y = entry.l, entry.h, entry.b1, entry.b2, entry.y

  local ok = pcall(function()
    g.removeAll()

    -- Frame
    graphics.quad(g, {0, y-b1}, {3.5*h+l+b2+1, y-b1}, {2.5*h+l+1, y-b1-h-b2}, {0, y-b1-h-b2}, cfg.borderColor, cfg)
    graphics.quad(g, {0, y}, {3.5*h+l+b2+1, y}, {3.5*h+l+b2+1, y-b1}, {0, y-b1}, cfg.borderColor, cfg)
    graphics.quad(g, {3.5*h, y-b1}, {3.5*h+l, y-b1}, {2.5*h+l, y-b1-h}, {2.5*h, y-b1-h}, cfg.secondaryColor, cfg)

    -- Energy bar + percentage
    entry.energyBar = graphics.quad(g, {b2+3.25*h, y-b1}, {b2+3.25*h, y-b1}, {b2+2.25*h, y-b1-h}, {b2+2.25*h, y-b1-h}, cfg.primaryColor, cfg)
    entry.textPercent = graphics.text(g, 'X.X%', {0.5*h, y-b1-h/1.8-cfg.fontSize}, cfg.fontSize, cfg.primaryColor, cfg)

    -- Curr / max EU
    entry.textCurr = graphics.text(g, '', {b2+3.25*h+1, y-b1-h/2-cfg.fontSize}, cfg.fontSize/1.3, cfg.textColor, cfg)
    entry.textMax  = graphics.text(g, '', {-2.25*h+l, y-b1-h/2-cfg.fontSize}, cfg.fontSize/1.3, cfg.textColor, cfg)

    -- History panel + maintenance line
    if cfg.showHistory then
      entry.historyPanel = graphics.drawHistoryPanel(g, cfg, y, l, h, b1, b2)
      local maintenanceY = entry.historyPanel.panelTop - cfg.historyBorderWidth - 3*cfg.fontSize
      entry.textMaintenance = graphics.text(g, '', {b2, maintenanceY}, cfg.fontSize, cfg.issueColor, cfg)
    else
      entry.historyPanel = nil
      entry.textMaintenance = graphics.text(g, '', {b2, y-b1-b2-h-3*cfg.fontSize}, cfg.fontSize, cfg.issueColor, cfg)
    end
  end)

  return ok
end

-- Initial discovery
for address in component.list('glasses') do
  local ok, proxy = pcall(component.proxy, component.get(address))
  if ok and proxy then
    local players = getCurrentPlayers(proxy)
    local cfg = config.resolve(players)
    local l, h, b1, b2, y = computeLayout(cfg)
    local entry = {
      proxy = proxy,
      address = address,
      players = players,
      cfg = cfg,
      lastPercent = 0,
      l = l, h = h, b1 = b1, b2 = b2, y = y,
    }
    if drawWidgets(entry) then
      table.insert(glasses, entry)
    end
  end
end

-- Stand Ready for Exit Command
events.hookEvents()

-- ===== MAIN LOOP =====
while true do

  -- Detect bind-list changes. When any terminal's bind list flips, OpenGlasses
  -- corrupts widgets on the *other* terminals. Redraw only those — never the
  -- terminal that just changed, because OpenGlasses is mid-handshake on that one
  -- and our removeAll() would race its widget restoration.
  local changedSet = {}
  local anyChanged = false
  for i = 1, #glasses do
    local entry = glasses[i]
    local current = getCurrentPlayers(entry.proxy)
    if playersChanged(entry.players, current) then
      entry.players = current
      entry.cfg = config.resolve(current)
      entry.l, entry.h, entry.b1, entry.b2, entry.y = computeLayout(entry.cfg)
      changedSet[i] = true
      anyChanged = true
    end
  end
  if anyChanged then
    for i = 1, #glasses do
      if not changedSet[i] then
        drawWidgets(glasses[i])
      end
    end
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

  for i = 1, #glasses do
    local entry = glasses[i]
    pcall(function()
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
