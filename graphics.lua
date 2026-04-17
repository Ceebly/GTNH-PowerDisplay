local graphics = {}
local config   = require('config')

function graphics.RGB(hex)
  local r = ((hex >> 16) & 0xFF) / 255.0
  local g = ((hex >> 8) & 0xFF) / 255.0
  local b = ((hex) & 0xFF) / 255.0
  return r, g, b
end

function graphics.quad(glasses, v1, v2, v3, v4, color, cfg)
  cfg = cfg or config
  local quad = glasses.addQuad()
  quad.setVertex(1, v1[1], v1[2])
  quad.setVertex(2, v2[1], v2[2])
  quad.setVertex(3, v3[1], v3[2])
  quad.setVertex(4, v4[1], v4[2])
  quad.setColor(graphics.RGB(color))
  quad.setAlpha(cfg.shapeAlpha)
  return quad
end

function graphics.text(glasses, string, v1, scale, color, cfg)
  cfg = cfg or config
  local text = glasses.addTextLabel()
  text.setText(string)
  text.setPosition(v1[1], v1[2])
  text.setScale(scale/3 or 1)
  text.setColor(graphics.RGB(color))
  text.setAlpha(cfg.textAlpha)
  return text
end

function graphics.metricParser(value) -- Creds: Vlamonster
  local units = {' ', 'K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y'}
  for i = 1, #units do
    if value < 1000 or i == #units then
      return string.format('%.1f%s', value, units[i])
    end
    value = value / 1000
  end
end

function graphics.scientificParser(value)
  value = string.format('%.2e', value)
  value = string.sub(value, 0, -4) .. string.sub(value, -2, -1)
  return value
end

function graphics.calcOffset(scale)
  if scale == 1 then
    return 71
  elseif scale == 2 then
    return 35
  elseif scale == 3 then
    return 23
  elseif scale == 4 then
    return 17
  else
    return 0
  end
end

function graphics.calcRate(percentage, last, threshold)
  if percentage > last + 2*threshold then
    return '>>>'
  elseif percentage > last + threshold then
    return '>>'
  elseif percentage >= last then
    return '>'
  elseif percentage > last - threshold then
    return '<'
  elseif percentage > last - 2*threshold then
    return '<<'
  else
    return '<<<'
  end
end

function graphics.formatDelta(value, useMetric)
  if value == nil then return 'N/A' end
  local prefix = ''
  if value > 0 then prefix = '+'
  elseif value < 0 then prefix = '-' end
  local absVal = math.abs(value)
  if useMetric then
    return prefix .. graphics.metricParser(absVal)
  else
    return prefix .. graphics.scientificParser(absVal)
  end
end

function graphics.formatRate(delta, windowSeconds, useMetric)
  if delta == nil then return 'N/A' end
  local rate = delta / windowSeconds / 20
  local prefix = ''
  if rate > 0 then prefix = '+'
  elseif rate < 0 then prefix = '-' end
  local absVal = math.abs(rate)
  if useMetric then
    return prefix .. graphics.metricParser(absVal) .. '/t'
  else
    return prefix .. graphics.scientificParser(absVal) .. '/t'
  end
end

function graphics.drawHistoryPanel(glasses, cfg, y, l, h, b1, b2)
  local ph = cfg.historyPanelHeight
  local bw = cfg.historyBorderWidth
  local fs = cfg.historyFontSize
  local panelBottom = y - b1 - h - b2
  local panelTop = panelBottom - ph
  local staticWidgets = {}

  -- Border (top and right edges, matching main bar's parallelogram slant)
  table.insert(staticWidgets, graphics.quad(glasses,
    {0, panelBottom},
    {2.5*h + l + bw + 1, panelBottom},
    {1.5*h + l + bw + 1, panelTop - bw},
    {0, panelTop - bw},
    cfg.historyBorderColor, cfg))

  -- Background (drawn on top of border, leaving border visible on top and right)
  table.insert(staticWidgets, graphics.quad(glasses,
    {0, panelBottom},
    {2.5*h + l + 1, panelBottom},
    {1.5*h + l + 1, panelTop},
    {0, panelTop},
    cfg.historyBgColor, cfg))

  local labels = cfg.historyLabels
  local windows = cfg.historyWindows
  local numWindows = math.min(#labels, #windows)
  local spacing = l / numWindows
  local lineSpacing = fs * 3 + 2

  local deltaTexts = {}
  local rateTexts = {}

  for i = 1, numWindows do
    local xPos = (i - 1) * spacing + 1.5*h
    local labelWidth = fs * (#labels[i] + 1) * 2

    -- Static label (e.g. "5m:")
    table.insert(staticWidgets, graphics.text(glasses, labels[i] .. ':',
      {xPos, panelTop + 2},
      fs, cfg.textColor, cfg))

    -- Delta + percentage value text (updated dynamically)
    if cfg.showHistoryDelta or cfg.showHistoryPercent then
      deltaTexts[i] = graphics.text(glasses, 'N/A',
        {xPos + labelWidth, panelTop + 2},
        fs, cfg.historyColor, cfg)
    end

    -- Rate value text (on second line)
    if cfg.showHistoryRate then
      rateTexts[i] = graphics.text(glasses, 'N/A',
        {xPos + labelWidth, panelTop + 2 + lineSpacing},
        fs, cfg.historyColor, cfg)
    end
  end

  return {deltaTexts = deltaTexts, rateTexts = rateTexts, panelBottom = panelBottom, panelTop = panelTop, staticWidgets = staticWidgets}
end

function graphics.fox()
  print('\27[34m' .. [[

                                   ⠀⢀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡀
         ███████╗ ██████╗ ██╗  ██╗  ⣾⠙⠻⢶⣄⡀⠀⠀⠀⢀⣤⠶⠛⠛⡇
         ██╔════╝██╔═══██╗╚██╗██╔╝  ⢹⣇⠀⠀⣙⣿⣦⣤⣴⣿⣁⠀⠀⣸⠇
         █████╗  ██║   ██║ ╚███╔╝   ⠀⠙⣡⣾⣿⣿⣿⣿⣿⣿⣿⣷⣌⠋
         ██╔══╝  ██║   ██║ ██╔██╗   ⠀⣴⣿⣷⣄⡈⢻⣿⡟⢁⣠⣾⣿⣦
         ██║     ╚██████╔╝██╔╝ ██╗  ⠀⢹⣿⣿⣿⣿⠘⣿⠃⣿⣿⣿⣿⡏
         ╚═╝      ╚═════╝ ╚═╝  ╚═╝   ⠀⣀⠀⠈⠛ ⠛ ⠛⠁⠀⣀
    ██╗  ██╗██╗   ██╗██████╗⠀       ⠀⢀⣼⣿⣦⠀   ⠀⣴⣿⡇
    ██║  ██║██║   ██║██╔══██⠀    ⣀⣤⣶⣾⣿⣿⣿⣿⡇⠀⠀⠀⢸⣿⣿
    ███████║██║   ██║██║  ██║⣠⣶⣿⣿⣿⣿⣿⣿⣿⣿⠿⠿⠀⠀⠀⠾⢿⣿⠃
    ██╔══██║██║   ██║██║  █⣠⣿⣿⣿⣿⣿⣿⡿⠟⠋⣁⣠⣤⣤⡶⠶⠶⣤⣄⠈
    ██║  ██║╚██████╔╝█████⢰⣿⣿⣮⣉⣉⣉⣤⣴⣶⣿⣿⣋⡥⠄⠀⠀⠀⠀⠉⢻⣄
    ╚═╝  ╚═╝ ╚═════╝⠀╚════⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⣋⣁⣤⣀⣀⣤⣤⣤⣤⣄⣿
                           ⠙⠿⣿⣿⣿⣿⣿⣿⣿⡿⠿⠛⠋⠉⠁⠀⠀⠀⠀⠈⠛
                             ⠀⠉⠉⠉⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
  ]] .. '\27[0m')
end

return graphics
