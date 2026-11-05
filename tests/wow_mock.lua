-- A small stand-in for the parts of the WoW API that JunkDrop uses. The tests load this first,
-- then the addon's own files. It proves logic, not looks or real client behavior.

tinsert = table.insert
SlashCmdList = {}
UISpecialFrames = {}
UIParent = {}
YES, NO = "Yes", "No"
NUM_BAG_SLOTS = 4
Enum = { BagIndex = { ReagentBag = 5 } }
ITEM_QUALITY0_DESC, ITEM_QUALITY1_DESC, ITEM_QUALITY2_DESC = "Poor", "Common", "Uncommon"
ITEM_QUALITY3_DESC, ITEM_QUALITY4_DESC = "Rare", "Epic"
ITEM_QUALITY_COLORS = {
  [0] = { hex = "|cff9d9d9d" }, { hex = "|cffffffff" }, { hex = "|cff1eff00" },
  { hex = "|cff0070dd" }, { hex = "|cffa335ee" },
}

-- Chat output, readable with FlushChat().
Chat = {}
ChatFrame1 = { AddMessage = function(_, message) tinsert(Chat, message) end }
function FlushChat()
  local text = table.concat(Chat, "\n")
  Chat = {}
  return text
end

function GetCoinTextureString(amount) return amount .. "c" end
C_Timer = { After = function(_, fn) fn() end } -- Run at once instead of later.

-- Time and combat. Tests move Now forward to start a new "frame".
Now = 100
function GetTime() return Now end
InCombat = false
function InCombatLockdown() return InCombat end

-- Confirmation windows are recorded instead of shown.
StaticPopupDialogs = {}
Popups = {}
function StaticPopup_Show(which, text, _, data) tinsert(Popups, { which = which, text = text, data = data }) end

-- The data-broker library: the addon's object is kept in LDB.
LibStub = { GetLibrary = function()
  return { NewDataObject = function(_, _, object) LDB = object; return object end }
end }

-- Frames, textures and animations. Any method not defined here does nothing and returns another
-- mock. A missing field therefore reads as a function (which is truthy), so use rawget to test
-- whether a field was really set.
local Mock
local function new(width, height) return setmetatable({ _w = width or 0, _h = height or 0 }, Mock) end
Textures, Groups, ChildFrames, EventHandlers = {}, {}, {}, {}
Mock = { __index = function(_, key)
  if key == "GetWidth" then return function(self) return self._w end end
  if key == "GetHeight" then return function(self) return self._h end end
  if key == "SetSize" then return function(self, w, h) self._w, self._h = w, h end end
  if key == "SetWidth" then return function(self, w) self._w = w end end
  if key == "SetHeight" then return function(self, h) self._h = h end end
  if key == "Show" then return function(self) self._shown = true end end
  if key == "Hide" then return function(self) self._shown = false end end
  if key == "IsShown" then return function(self) return self._shown == true end end
  if key == "GetFrameLevel" then return function() return 1 end end
  if key == "SetVertexColor" then return function(self, r, g, b) self._color = { r, g, b } end end
  if key == "SetColorTexture" then return function(self, r, g, b, a) self._solid = { r, g, b, a } end end
  if key == "SetTexture" then return function(self, path) self._path = path end end
  if key == "SetBlendMode" then return function(self, mode) self._blend = mode end end
  if key == "SetScript" then return function(_, name, fn) if name == "OnEvent" then tinsert(EventHandlers, fn) end end end
  if key == "CreateTexture" then
    return function(self)
      local texture = new()
      texture._shown, texture._owner = true, self
      tinsert(Textures, texture)
      return texture
    end
  end
  if key == "CreateAnimationGroup" then
    return function(self)
      local group = new()
      group._playing, group._owner = false, self
      group.Play = function(g) g._playing = true end
      group.Stop = function(g) g._playing = false end
      group.IsPlaying = function(g) return g._playing end
      group.CreateAnimation = function() return new() end
      tinsert(Groups, group)
      return group
    end
  end
  -- Child frames of the template have no such fields until something sets them.
  if key == "TitleText" or key == "Inset" or key == "CloseButton" then return nil end
  return function() return new() end
end }

-- Like the real client, a new frame is visible until it is hidden.
function CreateFrame(_, name, parent)
  local frame = new()
  frame._shown, frame._parent = true, parent
  if parent then tinsert(ChildFrames, frame) end
  if name == "JunkDropOptionsFrame" then OptionsWindow = frame end
  return frame
end

-- The bags: a list of { name, quality, vendor price, count, item class }. An emptied slot has
-- a blank name. Bag 0 holds everything.
bag = {}
Deleted = {}
local cursor
function SetBag(items) bag = items end
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and #bag or 0 end,
  GetContainerItemLink = function(b, s)
    local item = b == 0 and bag[s]
    return item and item[1] ~= "" and ("[" .. item[1] .. "]") or nil
  end,
  GetContainerItemInfo = function(b, s) local item = bag[s]; return item and { stackCount = item[4] } end,
  PickupContainerItem = function(_, s) cursor = s end,
}
function DeleteCursorItem()
  Deleted[#Deleted + 1] = bag[cursor][1]
  bag[cursor] = { "", -1, 0, 0, 0 }
  cursor = nil
end
C_Item = { GetItemInfo = function(link)
  local name = link:match("%[(.*)%]")
  for _, item in ipairs(bag) do
    if item[1] == name then return name, link, item[2], 1, 1, "", "", 1, "", 0, item[3], item[5] end
  end
end }

-- EllesmereUI Bags, as far as JunkDrop uses it: a button per slot, each with the overlay frame
-- painters draw on, and a repaint that calls every registered painter once per slot.
Buttons = {}
for slot = 1, 12 do
  local button = new(37, 37)
  button._textOverlay = new(37, 37)
  Buttons[slot] = button
end
Painters, Refreshes, BagsOpen = {}, 0, false
EUI_Bags = {
  RegisterItemOverlayIcon = function(name, fn) Painters[name] = fn end,
  IsShown = function() return BagsOpen end,
  RefreshInventory = function()
    Refreshes = Refreshes + 1
    for slot, button in ipairs(Buttons) do
      for _, fn in pairs(Painters) do fn(button, { bag = 0, slot = slot }) end
    end
  end,
}

-- Loading and test helpers.
NS = {} -- The table the addon files share (the second value WoW passes to each file).
function LoadFile(name, source) assert(loadstring(source, name))("JunkDrop", NS) end
function FireEvents() for _, fn in ipairs(EventHandlers) do fn() end end
function ResetState()
  JunkDropDB = nil
  Deleted, Popups, Chat = {}, {}, {}
  Refreshes, InCombat, BagsOpen = 0, false, false
  Now = Now + 1
end

-- Slots whose glow is showing, and whether the glow on a slot is pulsing.
function GlowingSlots()
  local lit = {}
  for slot, button in ipairs(Buttons) do
    local overlay = rawget(button, "_textOverlay")
    for _, frame in ipairs(ChildFrames) do
      if overlay and rawget(frame, "_parent") == overlay and rawget(frame, "_shown") then lit[#lit + 1] = slot end
    end
  end
  return table.concat(lit, ",")
end
function GlowPulsing(slot)
  local overlay = rawget(Buttons[slot], "_textOverlay")
  for _, frame in ipairs(ChildFrames) do
    if rawget(frame, "_parent") == overlay then
      for _, group in ipairs(Groups) do
        if rawget(group, "_owner") == frame and rawget(group, "_playing") then return true end
      end
    end
  end
  return false
end
