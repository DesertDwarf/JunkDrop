-- A small stand-in for the parts of the WoW API that JunkDrop uses. The tests load this first,
-- then the addon's own files. It proves logic, not looks or real client behavior.

tinsert = table.insert
SlashCmdList = {}

-- The client's bit library, as far as the addon uses it.
bit = { band = function(a, b)
  local result, place = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + place end
    a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
  end
  return result
end }
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
Textures, Groups, ChildFrames, EventFrames = {}, {}, {}, {}
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
  if key == "SetText" then return function(self, text) self._text = text end end
  -- Where things are placed, as { point, relative frame, relative point, x, y } in call order.
  if key == "SetPoint" then
    return function(self, ...)
      if not rawget(self, "_points") then self._points = {} end
      tinsert(self._points, { ... })
    end
  end
  if key == "ClearAllPoints" then return function(self) self._points = {} end end
  if key == "RegisterEvent" then
    return function(self, event)
      if not rawget(self, "_events") then
        self._events = {}
        tinsert(EventFrames, self)
      end
      self._events[event] = true
    end
  end
  if key == "SetScript" then return function(self, name, fn) if name == "OnClick" or name == "OnEvent" then self["_" .. name] = fn end end end
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
  if name == "JunkDropLootNote" then LootNote = frame end
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
  -- Free slots are the emptied ones; every bag is a general bag unless a test says otherwise.
  GetContainerNumFreeSlots = function(b)
    local free = 0
    for _, item in ipairs(b == 0 and bag or {}) do if item[1] == "" then free = free + 1 end end
    return free, BagFamilies[b] or 0
  end,
}
BagFamilies = {}
function DeleteCursorItem()
  Deleted[#Deleted + 1] = bag[cursor][1]
  bag[cursor] = { "", -1, 0, 0, 0 }
  cursor = nil
end
-- Bag items are { name, quality, price, count, class, max stack (1), item family (0) }.
-- Loot items are tables; see Loot below.
local function itemData(name)
  for _, item in ipairs(bag) do
    if item[1] == name then return item[2], item[3], item[5], item[6] or 1, item[7] or 0 end
  end
  for _, item in ipairs(Loot) do
    if item.name == name and not item.uncached then
      return item.quality, item.price, item.class, item.max, item.family
    end
  end
end
C_Item = {
  GetItemInfo = function(link)
    local name = link:match("%[(.*)%]")
    local quality, price, class, max = itemData(name)
    if quality then return name, link, quality, 1, 1, "", "", max, "", 134400, price, class end
  end,
  GetItemFamily = function(link) return select(5, itemData(link:match("%[(.*)%]"))) or 0 end,
}

-- The loot window: a list of { name, quality, price, qty, class, max, family, quest, slot } where
-- slot is the slot type (1 item, 2 money, 0 already looted). Missing fields get defaults.
Loot = {}
function SetLoot(items)
  Loot = items
  for _, item in ipairs(Loot) do
    item.qty, item.max, item.family = item.qty or 1, item.max or 1, item.family or 0
    item.slot, item.class, item.price = item.slot or 1, item.class or 15, item.price or 0
  end
end
function GetNumLootItems() return #Loot end
function GetLootSlotType(i) return Loot[i].slot end
function GetLootSlotInfo(i)
  local item = Loot[i]
  return 134400, item.name, item.qty, nil, item.quality, false, item.quest == true
end
function GetLootSlotLink(i) return Loot[i].slot == 1 and ("[" .. Loot[i].name .. "]") or nil end

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

-- Errors reported through the client's error handler.
Errors = {}
function geterrorhandler() return function(message) tinsert(Errors, message) end end

-- EllesmereUI's skinning hook, when a test asks for it: RegisterSkin records the registration, and
-- ApplySkin(failOn) then runs it with a skin object that records every call. The skin can be made
-- to throw on one call, as outside code might.
Registrations, SkinCalls = {}, {}
function MakeSkin(failOn)
  return setmetatable({}, { __index = function(_, name)
    return function(...)
      if name == failOn then error("simulated EllesmereUI failure in " .. name) end
      tinsert(SkinCalls, { name = name, args = { ... } })
    end
  end })
end
function ApplySkin(failOn)
  for _, registration in ipairs(Registrations) do registration.fn(MakeSkin(failOn)) end
end
function SkinHas(name, target)
  for _, call in ipairs(SkinCalls) do
    if call.name == name and call.args[1] == target then return true end
  end
  return false
end
function SkinCount(name)
  local count = 0
  for _, call in ipairs(SkinCalls) do if call.name == name then count = count + 1 end end
  return count
end

-- Loading and test helpers.
NS = {} -- The table the addon files share (the second value WoW passes to each file).
function LoadFile(name, source) assert(loadstring(source, name))("JunkDrop", NS) end
-- Deliver an event to every frame that registered for it, as the client does.
function FireEvent(event, ...)
  for _, frame in ipairs(EventFrames) do
    if frame._events[event] and rawget(frame, "_OnEvent") then frame._OnEvent(frame, event, ...) end
  end
end
function ResetState()
  JunkDropDB = nil
  Deleted, Popups, Chat, Loot, BagFamilies, Errors = {}, {}, {}, {}, {}, {}
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
