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

-- Compute layout from global config
local l  = config.length
local h  = config.height
local b1 = config.borderBottom
local b2 = config.borderTop
local y  = config.resolution[2] / config.GUIscale
if not config.fullscreen then
  y = y - graphics.calcOffset(config.GUIscale)
end

-- Discover glasses and draw static widgets
for address in component.list('glasses') do
  local g = component.proxy(component.get(address))
  g.removeAll()

  -- Frame
  graphics.quad(g, {0, y-b1}, {3.5*h+l+b2+1, y-b1}, {2.5*h+l+1, y-b1-h-b2}, {0, y-b1-h-b2}, config.borderColor)
  graphics.quad(g, {0, y}, {3.5*h+l+b2+1, y}, {3.5*h+l+b2+1, y-b1}, {0, y-b1}, config.borderColor)
  graphics.quad(g, {3.5*h, y-b1}, {3.5*h+l, y-b1}, {2.5*h+l, y-b1-h}, {2.5*h, y-b1-h}, config.secondaryColor)

  local entry = {
    proxy = g,
    lastPercent = 0,
  }

  -- Energy bar + percentage
  entry.energyBar = graphics.quad(g, {b2+3.25*h, y-b1}, {b2+3.25*h, y-b1}, {b2+2.25*h, y-b1-h}, {b2+2.25*h, y-b1-h}, config.primaryColor)
  entry.textPercent = graphics.text(g, 'X.X%', {0.5*h, y-b1-h/1.8-config.fontSize}, config.fontSize, config.primaryColor)

  -- Curr / max EU
  entry.textCurr = graphics.text(g, '', {b2+3.25*h+1, y-b1-h/2-config.fontSize}, config.fontSize/1.3, config.textColor)
  entry.textMax  = graphics.text(g, '', {-2.25*h+l, y-b1-h/2-config.fontSize}, config.fontSize/1.3, config.textColor)

  -- History panel + maintenance line
  if config.showHistory then
    entry.historyPanel = graphics.drawHistoryPanel(g, config, y, l, h, b1, b2)
    local maintenanceY = entry.historyPanel.panelTop - config.historyBorderWidth - 3*config.fontSize
    entry.textMaintenance = graphics.text(g, '', {b2, maintenanceY}, config.fontSize, config.issueColor)
  else
    entry.textMaintenance = graphics.text(g, '', {b2, y-b1-b2-h-3*config.fontSize}, config.fontSize, config.issueColor)
  end

  table.insert(glasses, entry)
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
    local entry = glasses[i]

    -- Adjust Values
    local curr = ''
    if config.showCurrentEU then
      if config.metric then
        curr = graphics.metricParser(power)
      else
        curr = graphics.scientificParser(power)
      end
    end

    local rate = ''
    if config.showRate then
      rate = graphics.calcRate(percentage, entry.lastPercent, config.rateThreshold)
      entry.lastPercent = percentage
    end

    -- Adjust Energy Bar
    entry.energyBar.setVertex(2, b2+3.25*h+l*percentage, y-b1)
    entry.energyBar.setVertex(3, b2+2.25*h+l*percentage, y-b1-h)

    if percentage > 0.999 then
      entry.textPercent.setText('100%')
      entry.textPercent.setPosition(b2+2.1*h-2*config.fontSize*(#entry.textPercent.getText()), y-b1-h/1.8-config.fontSize)
    else
      entry.textPercent.setText(string.format('%.1f%%', percentage*100))
      entry.textPercent.setPosition(b2+2*h-2*config.fontSize*(#entry.textPercent.getText()-1), y-b1-h/1.8-config.fontSize)
    end

    entry.textCurr.setText(curr .. ' ' .. rate)

    if config.showMaxEU then
      local maxText
      if config.metric then
        maxText = graphics.metricParser(capacity)
      else
        maxText = graphics.scientificParser(capacity)
      end
      entry.textMax.setText(maxText)
      entry.textMax.setPosition(2.25*h+l-1.5*config.fontSize*(#entry.textMax.getText()-1), y-b1-h/2-config.fontSize)
    end

    -- Detect Maintenance Issues
    if #scan[17] < 43 then
      entry.textMaintenance.setText('Has Problems!')
    else
      entry.textMaintenance.setText('')
    end

    -- Update History Panel
    if config.showHistory and entry.historyPanel then
      local windows = config.historyWindows
      local deltas = history.getDeltas(windows)
      local panel = entry.historyPanel

      for w = 1, math.min(#deltas, #config.historyLabels) do
        if panel.deltaTexts[w] then
          local deltaText = ''
          if config.showHistoryDelta then
            deltaText = graphics.formatDelta(deltas[w], config.metric)
          end
          if config.showHistoryPercent and deltas[w] ~= nil then
            local pct = string.format('%.1f%%', deltas[w] / capacity * 100)
            if deltas[w] > 0 then pct = '+' .. pct end
            if deltaText ~= '' then
              deltaText = deltaText .. ' (' .. pct .. ')'
            else
              deltaText = pct
            end
          elseif config.showHistoryPercent then
            if deltaText == '' then deltaText = 'N/A' end
          end
          panel.deltaTexts[w].setText(deltaText)
          if deltas[w] == nil then
            panel.deltaTexts[w].setColor(graphics.RGB(config.textColor))
          elseif deltas[w] >= 0 then
            panel.deltaTexts[w].setColor(graphics.RGB(config.primaryColor))
          else
            panel.deltaTexts[w].setColor(graphics.RGB(config.issueColor))
          end
        end

        if config.showHistoryRate and panel.rateTexts[w] then
          local rateText = graphics.formatRate(deltas[w], windows[w], config.metric)
          panel.rateTexts[w].setText(rateText)
          if deltas[w] == nil then
            panel.rateTexts[w].setColor(graphics.RGB(config.textColor))
          elseif deltas[w] >= 0 then
            panel.rateTexts[w].setColor(graphics.RGB(config.primaryColor))
          else
            panel.rateTexts[w].setColor(graphics.RGB(config.issueColor))
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
