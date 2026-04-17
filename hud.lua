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

for address in component.list('glasses') do
  local proxy = component.proxy(component.get(address))
  local players = proxy.getBindPlayers()
  table.insert(glasses, {
    proxy = proxy,
    players = players,
    cfg = config.resolve(players),
    lastPercent = 0,
  })
end

-- Configure and Draw Per-Glasses
for i = 1, #glasses do
  local g = glasses[i].proxy
  local cfg = glasses[i].cfg
  local l  = cfg.length
  local h  = cfg.height
  local b1 = cfg.borderBottom
  local b2 = cfg.borderTop
  local y  = cfg.resolution[2] / cfg.GUIscale

  if not cfg.fullscreen then
    y = y - graphics.calcOffset(cfg.GUIscale)
  end

  -- Store layout for main loop
  glasses[i].y  = y
  glasses[i].l  = l
  glasses[i].h  = h
  glasses[i].b1 = b1
  glasses[i].b2 = b2

  g.removeAll()

  -- Draw Static Shapes
  graphics.quad(g, {0, y-b1}, {3.5*h+l+b2+1, y-b1}, {2.5*h+l+1, y-b1-h-b2}, {0, y-b1-h-b2}, cfg.borderColor, cfg)
  graphics.quad(g, {0, y}, {3.5*h+l+b2+1, y}, {3.5*h+l+b2+1, y-b1}, {0, y-b1}, cfg.borderColor, cfg)
  graphics.quad(g, {3.5*h, y-b1}, {3.5*h+l, y-b1}, {2.5*h+l, y-b1-h}, {2.5*h, y-b1-h}, cfg.secondaryColor, cfg)

  -- Draw Energy Bar
  glasses[i].energyBar = graphics.quad(g, {b2+3.25*h, y-b1}, {b2+3.25*h, y-b1}, {b2+2.25*h, y-b1-h}, {b2+2.25*h, y-b1-h}, cfg.primaryColor, cfg)
  glasses[i].textPercent = graphics.text(g, 'X.X%', {0.5*h, y-b1-h/1.8-cfg.fontSize}, cfg.fontSize, cfg.primaryColor, cfg)

  -- Draw Optional Values
  glasses[i].textCurr = graphics.text(g, '', {b2+3.25*h+1, y-b1-h/2-cfg.fontSize}, cfg.fontSize/1.3, cfg.textColor, cfg)
  glasses[i].textMax = graphics.text(g, '', {-2.25*h+l, y-b1-h/2-cfg.fontSize}, cfg.fontSize/1.3, cfg.textColor, cfg)

  -- History Panel
  if cfg.showHistory then
    glasses[i].historyPanel = graphics.drawHistoryPanel(g, cfg, y, l, h, b1, b2)
    -- Maintenance text above history panel
    local maintenanceY = glasses[i].historyPanel.panelTop - cfg.historyBorderWidth - 3*cfg.fontSize
    glasses[i].textMaintenance = graphics.text(g, '', {b2, maintenanceY}, cfg.fontSize, cfg.issueColor, cfg)
  else
    glasses[i].textMaintenance = graphics.text(g, '', {b2, y-b1-b2-h-3*cfg.fontSize}, cfg.fontSize, cfg.issueColor, cfg)
  end
end

-- Stand Ready for Exit Command
events.hookEvents()

-- ===== MAIN LOOP =====
while true do

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
    local cfg = glasses[i].cfg
    local g   = glasses[i].proxy
    local y   = glasses[i].y
    local l   = glasses[i].l
    local h   = glasses[i].h
    local b1  = glasses[i].b1
    local b2  = glasses[i].b2

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
      rate = graphics.calcRate(percentage, glasses[i].lastPercent, cfg.rateThreshold)
      glasses[i].lastPercent = percentage
    end

    -- Adjust Energy Bar
    glasses[i].energyBar.setVertex(2, b2+3.25*h+l*percentage, y-b1)
    glasses[i].energyBar.setVertex(3, b2+2.25*h+l*percentage, y-b1-h)

    if percentage > 0.999 then
      glasses[i].textPercent.setText('100%')
      glasses[i].textPercent.setPosition(b2+2.1*h-2*cfg.fontSize*(#glasses[i].textPercent.getText()), y-b1-h/1.8-cfg.fontSize)
    else
      glasses[i].textPercent.setText(string.format('%.1f%%', percentage*100))
      glasses[i].textPercent.setPosition(b2+2*h-2*cfg.fontSize*(#glasses[i].textPercent.getText()-1), y-b1-h/1.8-cfg.fontSize)
    end

    glasses[i].textCurr.setText(curr .. ' ' .. rate)

    if cfg.showMaxEU then
      local maxText
      if cfg.metric then
        maxText = graphics.metricParser(capacity)
      else
        maxText = graphics.scientificParser(capacity)
      end
      glasses[i].textMax.setText(maxText)
      glasses[i].textMax.setPosition(2.25*h+l-1.5*cfg.fontSize*(#glasses[i].textMax.getText()-1), y-b1-h/2-cfg.fontSize)
    end

    -- Detect Maintenance Issues
    if #scan[17] < 43 then
      glasses[i].textMaintenance.setText('Has Problems!')
    else
      glasses[i].textMaintenance.setText('')
    end

    -- Update History Panel
    if cfg.showHistory and glasses[i].historyPanel then
      local windows = cfg.historyWindows
      local deltas = history.getDeltas(windows)
      local panel = glasses[i].historyPanel

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
  glasses[i].proxy.removeAll()
end
