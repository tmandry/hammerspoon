local hints = require "hs.hints.internal"
-- If you don't have a C or Objective-C submodule, the above line gets simpler:
-- local foobar = {}
-- Always return your top-level module; never set globals.
local screen = require "hs.screen"
local window = require "hs.window"
local hotkey = require "hs.hotkey"
local modal_hotkey = hotkey.modal

--- hs.hints.hintChars
--- Variable
--- This controls the set of characters that will be used for window hints
--- Defaults to: {"A","O","E","U","I","D","H","T","N","S","P","G","M","W","V","J","K","X","B","Y","F"}
hints.hintChars = {"A","O","E","U","I","D","H","T","N","S","P","G",
                   "M","W","V","J","K","X","B","Y","F"}

local openHints = {}
local takenPositions = {}
local hintDict = {}
local modalKey = nil

local bumpThresh = 40^2
local bumpMove = 80
function hints.bumpPos(x,y)
  for i, pos in ipairs(takenPositions) do
    if ((pos.x-x)^2 + (pos.y-y)^2) < bumpThresh then
      return hints.bumpPos(x,y+bumpMove)
    end
  end

  return {x = x,y = y}
end

function hints.createHandler(char)
  return function()
    local win = hintDict[char]
    if win then win:focus() end
    hints.closeHints()
    modalKey:exit()
  end
end

function hints.setupModal()
  k = modal_hotkey.new({"cmd", "shift"}, "V")
  k:bind({}, 'escape', function() hints.closeHints(); k:exit() end)

  for i,c in ipairs(hints.hintChars) do
    k:bind({}, c, hints.createHandler(c))
  end
  return k
end
modalKey = hints.setupModal()

function hints.windowHints()
  hints.closeHints()
  for i,win in ipairs(window.allWindows()) do
    local app = win:application()
    local fr = win:frame()
    local sfr = win:screen():frame()
    if app and win:title() ~= "" then
      local c = {x = fr.x + (fr.w/2) - sfr.x, y = fr.y + (fr.h/2) - sfr.y}
      c = hints.bumpPos(c.x, c.y)
      print(win:title().." x:"..c.x.." y:"..c.y)
      local hint = hints.new(c.x,c.y,hints.hintChars[i],app:bundleID(),win:screen())
      hintDict[hints.hintChars[i]] = win
      table.insert(takenPositions, c)
      table.insert(openHints, hint)
    end
  end
  modalKey:enter()
end

function hints.closeHints()
  for i, hint in ipairs(openHints) do
    hint:close()
  end
  openHints = {}
  hintDict = {}
  takenPositions = {}
end

return hints
