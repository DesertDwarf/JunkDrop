-- Loot.lua
-- When the loot window is open and your bags are full, a small note beside it says, for each item
-- that won't fit, whether it is worth taking and which of your items JunkDrop would drop to make
-- room. The note is a frame of our own, so it works with any loot window.

local _, JD = ... -- Addon name and the table shared between this addon's files.

-- Container functions moved into C_Container, and the old globals are gone in modern clients.
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerNumFreeSlots = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemFamily = C_Item and C_Item.GetItemFamily or GetItemFamily

local ItemSlotType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or LOOT_SLOT_ITEM or 1
local QuestClassID = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
local MaxItems = 4 -- Items the note lists; more are summarized in a last line.
local NoteWidth, MinWidth = 380, 340

-- Items and bags carry a "family" bit mask for specialty bags (herbs, gems, and so on). A bag
-- with family 0 takes anything; any other bag takes only items sharing a bit with it.
local function Fits(ItemFamily, BagFamily)
  return BagFamily == 0 or (ItemFamily or 0) > 0 and bit.band(ItemFamily, BagFamily) ~= 0
end

-- The same item can have many links (different bonuses), so stacks are matched by item ID.
local function ItemKey(Link)
  return tonumber(string.match(Link or "", "item:(%d+)")) or Link
end

-- Read the loot window into a list of items that need bag space (money and currency don't).
local function ReadLoot()
  local Items = {}
  for Slot = 1, GetNumLootItems() do
    if GetLootSlotType(Slot) == ItemSlotType then -- A looted slot reads as a different type.
      local Icon, _, Quantity, _, _, _, IsQuest = GetLootSlotInfo(Slot)
      local Link = GetLootSlotLink(Slot)
      if Link then
        local Name, _, _, _, _, _, _, MaxStack, _, _, SellPrice, ClassID = GetItemInfo(Link)
        tinsert(Items, {
          Slot = Slot,
          Link = Link,
          Name = Name,
          Icon = Icon,
          Quantity = Quantity or 1,
          -- The class check backs up the flag, whose position in the return list varies by client.
          IsQuest = IsQuest == true or ClassID == QuestClassID,
          MaxStack = MaxStack or 1,
          Key = ItemKey(Link),
          Family = GetItemFamily and GetItemFamily(Link) or 0,
          Price = SellPrice, -- nil until the client has the item's data
        })
      end
    end
  end
  return Items
end

-- Read the bags: how many free slots each has, and how much room each stackable item still has
-- in partly filled stacks (a new item of that kind can join those even when no slot is free).
local function ReadBags()
  local Bags, Room = {}, {}
  for Bag = 0, JD.LastBag do
    if GetContainerNumSlots(Bag) > 0 then
      local Free, Family = GetContainerNumFreeSlots(Bag)
      tinsert(Bags, { Bag = Bag, Free = Free or 0, Family = Family or 0 })
    end
  end
  JD.ForEachBagItem(function(Bag, Slot, Link)
    local _, _, _, _, _, _, _, MaxStack = GetItemInfo(Link)
    local Count = JD.GetStackCount(Bag, Slot) or 1
    if MaxStack and MaxStack > Count then
      local Key = ItemKey(Link)
      Room[Key] = (Room[Key] or 0) + MaxStack - Count
    end
  end)
  return Bags, Room
end

-- Decide what to do about each loot item. Items that fit are left out. Each that doesn't gets one
-- of these Actions, best loot first:
--   swap     worth more than the next stack JunkDrop would drop: take it and drop that stack
--   skip     worth no more than that stack: leave it
--   none     no room, and JunkDrop has nothing it may drop that would make room
--   unknown  no vendor price, so there is nothing to compare; the player decides
--   pending  the client has not loaded the item's data yet, so it cannot be judged yet
-- Quest items are always worth taking. Candidates are JunkDrop's stacks in drop order.
local function PlanLoot(Items, Bags, Room, Candidates)
  local BagFamily = {}
  for _, Bag in ipairs(Bags) do
    BagFamily[Bag.Bag] = Bag.Family
  end

  local Needing = {}
  for _, Item in ipairs(Items) do
    local Joinable = Room[Item.Key]
    if Item.MaxStack > 1 and Joinable and Joinable >= Item.Quantity then
      Room[Item.Key] = Joinable - Item.Quantity -- It joins a partly filled stack.
    else
      -- Prefer a specialty bag made for the item, so the general bags stay free.
      local Chosen
      for _, Bag in ipairs(Bags) do
        if Bag.Free > 0 and Fits(Item.Family, Bag.Family) then
          if Bag.Family ~= 0 then
            Chosen = Bag
            break
          end
          Chosen = Chosen or Bag -- A general bag is the fallback.
        end
      end
      if Chosen then
        Chosen.Free = Chosen.Free - 1
      else
        if Item.Price and Item.Price > 0 then
          Item.Value = Item.Price * Item.Quantity
        end
        tinsert(Needing, Item)
      end
    end
  end

  -- Quest items first, then by value, so the best loot gets the first stacks that can go.
  table.sort(Needing, function(A, B)
    if A.IsQuest ~= B.IsQuest then
      return A.IsQuest
    end
    return (A.Value or -1) > (B.Value or -1)
  end)

  local Used, Results = {}, {}
  for _, Item in ipairs(Needing) do
    local Result = { Item = Item }
    if not Item.IsQuest and Item.Price == nil then
      Result.Action = "pending" -- The client has not loaded the item yet; we are told when it has.
    elseif not Item.IsQuest and not Item.Value then
      Result.Action = "unknown"
    else
      for Rank, Stack in ipairs(Candidates) do
        if not Used[Rank] and Fits(Item.Family, BagFamily[Stack.Bag] or 0) then
          Result.Candidate, Result.Rank = Stack, Rank
          break
        end
      end
      if not Result.Candidate then
        Result.Action = "none"
      elseif Item.IsQuest or Item.Value > Result.Candidate.Value then
        Result.Action = "swap"
        Used[Result.Rank] = true
      else
        Result.Action = "skip"
      end
    end
    tinsert(Results, Result)
  end
  return Results
end

-- The note: two labeled lines for each item that doesn't fit.
local Green, Red, Grey = "|cff40ff40", "|cffff4040", "|cffaaaaaa"
local Pad, LineHeight, ItemGap, LabelWidth = 14, 16, 8, 38 -- Pad clears the border drawn around the note.

-- The look of Blizzard's own dialog windows, so the note sits comfortably beside the loot window.
local Backdrop = {
  bgFile = "Interface\DialogFrame\UI-DialogBox-Background",
  edgeFile = "Interface\DialogFrame\UI-DialogBox-Border",
  tile = true,
  tileSize = 32,
  edgeSize = 24,
  insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

local function WithIcon(Icon, Link, Quantity)
  local Text = "|T" .. (Icon or 134400) .. ":14|t " .. Link
  if Quantity and Quantity > 1 then
    Text = Text .. " x" .. Quantity
  end
  return Text
end

-- Returns the labeled lines for one planned item as TopLabel, Top, BottomLabel, Bottom. A swap is a
-- checklist in the order to do it: drop the bag item, then take the loot. Anything else is the loot
-- with the reason underneath.
local function Describe(Result)
  local Item, Stack = Result.Item, Result.Candidate
  local Loot = WithIcon(Item.Icon, Item.Link, Item.Quantity)
  if Item.Value then
    Loot = Loot .. "  " .. JD.FormatCoins(Item.Value)
  end

  if Result.Action == "swap" then
    local Drop = WithIcon(Stack.Icon, Stack.Link, Stack.Count) .. "  " .. JD.FormatCoins(Stack.Value)
    local Take = Item.IsQuest and (Loot .. "  " .. Grey .. "(quest item)|r") or Loot
    return Red .. "Drop|r", Drop, Green .. "Take|r", Take
  elseif Result.Action == "skip" then
    return Red .. "Skip|r", Loot, "", Grey .. "not worth more than " .. Stack.Link .. " " .. JD.FormatCoins(Stack.Value) .. "|r"
  elseif Result.Action == "none" then
    return Red .. "Skip|r", Loot, "", Grey .. "No room, and nothing JunkDrop can drop|r"
  elseif Result.Action == "pending" then
    return Grey .. "...|r", Loot, "", Grey .. "Checking this item...|r"
  end
  return Grey .. "Check|r", Loot, "", Grey .. "No vendor price, your call|r"
end

local Note -- Built the first time it is needed.
local LootOpen = false

-- With EllesmereUI, the player's theme paints the note: its panel and border replace our plain
-- black background and red edge, its button style goes on ours, and its font on every line. The
-- red and green words keep their meaning. EllesmereUI's code is outside ours, so a failure in it
-- is reported but never stops the note from working.
local function SkinNote(S)
  if Note.SetBackdrop then
    Note:SetBackdrop(nil) -- The theme draws its own panel, so the dialog border would double up.
  end
  S.Panel(Note)
  Note.Background:Hide()
  for _, Edge in ipairs(Note.Edges) do
    Edge:Hide()
  end
  S.Button(Note.DropButton)
  S.Font(Note.Header)
  for _, Slot in ipairs(Note.Items) do
    for _, Part in ipairs({ "TopLabel", "Top", "BottomLabel", "Bottom" }) do
      S.Font(Slot[Part])
    end
  end
end

function JD.ApplyLootSkin(S)
  if Note then
    local Ok, Err = pcall(SkinNote, S)
    if not Ok then
      geterrorhandler()(Err)
    end
  end
end

JD.OnSkin(JD.ApplyLootSkin)

local function BuildNote()
  -- Modern clients draw a frame's backdrop only if it is made from the BackdropTemplate.
  Note = CreateFrame("Frame", "JunkDropLootNote", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Note:SetFrameStrata("HIGH")
  Note:Hide() -- New frames start out visible.

  Note.Background = Note:CreateTexture(nil, "BACKGROUND")
  Note.Background:SetAllPoints(Note)
  Note.Background:SetColorTexture(0, 0, 0, .85)
  Note.Edges = {}

  -- A thin red edge, so the note reads as a warning and is easy to find beside the loot.
  for _, Corners in ipairs({
    { "TOPLEFT", "TOPRIGHT", "Height" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "Height" },
    { "TOPLEFT", "BOTTOMLEFT", "Width" }, { "TOPRIGHT", "BOTTOMRIGHT", "Width" },
  }) do
    local Edge = Note:CreateTexture(nil, "BORDER")
    Edge:SetColorTexture(1, .25, .25, .9)
    Edge:SetPoint(Corners[1], Note, Corners[1])
    Edge:SetPoint(Corners[2], Note, Corners[2])
    Edge["Set" .. Corners[3]](Edge, 1)
    tinsert(Note.Edges, Edge)
  end

  -- With a backdrop the plain black fill and red edge above are not needed; they remain only for a
  -- client that cannot draw one.
  if Note.SetBackdrop then
    Note:SetBackdrop(Backdrop)
    Note.Background:Hide()
    for _, Edge in ipairs(Note.Edges) do
      Edge:Hide()
    end
  end

  Note.Header = Note:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Note.Items = {}
  for Index = 1, MaxItems do
    local Slot = {}
    for _, Part in ipairs({ "TopLabel", "Top", "BottomLabel", "Bottom" }) do
      Slot[Part] = Note:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      Slot[Part]:SetJustifyH("LEFT")
      Slot[Part]:SetWordWrap(false)
    end
    Note.Items[Index] = Slot
  end

  Note.DropButton = CreateFrame("Button", nil, Note, "UIPanelButtonTemplate")
  Note.DropButton:SetHeight(22)
  Note.DropButton:SetText("Drop the suggested items")
  Note.DropButton:SetScript("OnClick", function()
    JD.DropStacks(Note.Swaps, JD.Get("ReportDrops"))
  end)

  if JD.Skin then
    JD.ApplyLootSkin(JD.Skin)
  end
end

-- Under the loot window, as wide as it is (but wide enough to read).
local function Place()
  Note:ClearAllPoints()
  -- ElvUI replaces the loot window with its own; everyone else uses Blizzard's.
  local Target = _G.ElvLootFrame or _G.LootFrame
  if Target and Target:IsShown() then
    Note:SetWidth(math.max(Target:GetWidth() or 0, MinWidth))
    Note:SetPoint("TOP", Target, "BOTTOM", 0, -4)
  else
    Note:SetWidth(NoteWidth)
    Note:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  end
end

-- A line of text, stretched from after the label column to the note's right edge.
local function Put(Line, Y)
  Line:ClearAllPoints()
  Line:SetPoint("TOPLEFT", Note, "TOPLEFT", Pad + LabelWidth + 4, -Y)
  Line:SetPoint("TOPRIGHT", Note, "TOPRIGHT", -Pad, -Y)
end

-- A short label in the column to the left of the text.
local function PutLabel(Line, Y)
  Line:ClearAllPoints()
  Line:SetPoint("TOPLEFT", Note, "TOPLEFT", Pad, -Y)
  Line:SetWidth(LabelWidth)
end

local function HideNote()
  if Note then
    Note:Hide()
  end
end

-- Work out what the note should say right now and show or hide it.
local function Update()
  if not (LootOpen and JD.Get("LootNote")) then
    HideNote()
    return
  end

  local Bags, Room = ReadBags()
  local Results = PlanLoot(ReadLoot(), Bags, Room, JD.GetJunkStacks())
  if #Results == 0 then
    HideNote() -- Everything fits, so there is nothing to decide.
    return
  end

  if not Note then
    BuildNote()
  end
  Place()

  Note.Swaps = {}
  for _, Result in ipairs(Results) do
    if Result.Action == "swap" then
      tinsert(Note.Swaps, Result.Candidate)
    end
  end

  Note.Header:ClearAllPoints()
  Note.Header:SetPoint("TOPLEFT", Note, "TOPLEFT", Pad, -Pad)
  Note.Header:SetText(Red .. "Bags full|r  " .. Grey .. "JunkDrop's advice for this loot|r")

  -- With more items than slots, the last slot says how many are not shown.
  local Shown = #Results > MaxItems and MaxItems - 1 or #Results
  local Y = Pad + LineHeight + 6
  for Index, Slot in ipairs(Note.Items) do
    if Index <= Shown then
      local TopLabel, Top, BottomLabel, Bottom = Describe(Results[Index])
      Slot.TopLabel:SetText(TopLabel)
      Slot.Top:SetText(Top)
      Slot.BottomLabel:SetText(BottomLabel)
      Slot.Bottom:SetText(Bottom)
      PutLabel(Slot.TopLabel, Y)
      Put(Slot.Top, Y)
      PutLabel(Slot.BottomLabel, Y + LineHeight)
      Put(Slot.Bottom, Y + LineHeight)
      Y = Y + 2 * LineHeight + ItemGap
    elseif Index == Shown + 1 and #Results > Shown then
      Slot.TopLabel:SetText("")
      Slot.Top:SetText(Grey .. "...and " .. (#Results - Shown) .. " more|r")
      Put(Slot.Top, Y)
      Slot.BottomLabel:SetText("")
      Slot.Bottom:SetText("")
      Y = Y + LineHeight + ItemGap
    else
      for _, Part in ipairs({ "TopLabel", "Top", "BottomLabel", "Bottom" }) do
        Slot[Part]:SetText("")
      end
    end
  end

  local Height = Y - ItemGap + Pad
  local Button = Note.DropButton
  Button:ClearAllPoints()
  if JD.Get("LootDrop") and #Note.Swaps > 0 then
    Button:SetPoint("BOTTOMLEFT", Note, "BOTTOMLEFT", Pad, Pad)
    Button:SetPoint("BOTTOMRIGHT", Note, "BOTTOMRIGHT", -Pad, Pad)
    Button:Show()
    Height = Height + 8 + 22
  else
    Button:Hide()
  end
  Note:SetHeight(Height)
  Note:Show()
end

JD.PlanLoot = PlanLoot
JD.ReadLoot = ReadLoot
JD.ReadBags = ReadBags
JD.RefreshLoot = Update

local Events = CreateFrame("Frame")
for _, Event in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
  Events:RegisterEvent(Event)
end
Events:SetScript("OnEvent", function(_, Event)
  if Event == "LOOT_OPENED" then
    LootOpen = true
    Update()
    -- The loot window may not be showing yet when this runs, so look again to anchor the note to it.
    C_Timer.After(.1, Update)
  elseif Event == "LOOT_CLOSED" then
    LootOpen = false
    HideNote()
  elseif LootOpen then
    Update() -- A slot was looted, the bags changed, or an item's data arrived.
  end
end)
