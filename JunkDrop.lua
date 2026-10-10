-- JunkDrop.lua
-- by: desertdwarf

local _, JD = ... -- Addon name and the table shared between this addon's files.

-- Container/item APIs moved into C_Container/C_Item in modern clients and the old
-- globals are gone there. Bind locals so call sites below work on either API.
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
local PickupContainerItem = C_Container and C_Container.PickupContainerItem or PickupContainerItem
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

-- C_Container.GetContainerItemInfo returns a table; the legacy global returns multiple values.
local function GetStackCount(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount
  end
  return select(2, GetContainerItemInfo(bag, slot))
end

-- Newer clients expose the coin formatter under C_CurrencyInfo; older ones only have the global.
local GetCoinTextureString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString

-- Saved settings live in JunkDropDB (declared in the TOC). The client fills that table in after
-- this file runs, so reads fall back to the defaults until then.
JD.Defaults = {
  Label = "full", -- Text before the item on LDB displays: "full" (JunkDrop), "short" (JD) or "none".
  Show = "both", -- What LDB displays show: "both" (item name and value), "value" or "name".
  ShowCount = true, -- Append the stack size (x3) when a stack holds more than one item.
  Coins = "icons", -- Coin style: "icons" or "letters" (1g 2s 3c).
  TooltipRows = 5, -- Cheapest stacks listed in the LDB tooltip.
  ConfirmClick = false, -- Ask before an LDB click deletes anything.
  ReportDrops = true, -- Print each deleted stack to chat.
  Include0 = true, -- Item qualities that may be dropped: 0 Poor (grey), 1 Common, 2 Uncommon,
  Include1 = false, -- 3 Rare, 4 Epic. Only Poor is on by default.
  Include2 = false,
  Include3 = false,
  Include4 = false,
  Order = "quality", -- Drop order: "quality" (lowest quality first, then cheapest) or "price" (cheapest first).
  ConfirmHigher = true, -- Ask before deleting anything better than Poor.
}

local function SettingsChanged()
  if JD.RefreshText then
    JD.RefreshText()
  end
end

function JD.Get(Key)
  local Value = JunkDropDB and JunkDropDB[Key]
  if Value == nil then
    return JD.Defaults[Key]
  end
  return Value
end

function JD.Set(Key, Value)
  JunkDropDB = JunkDropDB or {}
  JunkDropDB[Key] = Value
  SettingsChanged()
end

function JD.Reset()
  JunkDropDB = {}
  SettingsChanged()
end

-- Formats a copper amount as coins, in the style chosen in the settings.
local function FormatCoins(Amount)
  if JD.Get("Coins") == "icons" then
    return GetCoinTextureString(Amount)
  end
  local Gold = math.floor(Amount / 10000)
  local Silver = math.floor((Amount % 10000) / 100)
  local Text = ""
  if Gold > 0 then
    Text = Gold .. "|cffffd700g|r "
  end
  if Gold > 0 or Silver > 0 then
    Text = Text .. Silver .. "|cffc7c7cfs|r "
  end
  return Text .. (Amount % 100) .. "|cffeda55fc|r"
end

-- Retail added a reagent bag after the four regular bags; older clients stop at NUM_BAG_SLOTS.
local LastBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or NUM_BAG_SLOTS

local function Say(Message)
  ChatFrame1:AddMessage("JunkDrop: " .. Message, .69, .49, 1.0)
end

local HelpLines = {
  "Deletes the lowest-value items in your bags. It does not sell them.",
  "Only Poor (grey) items are considered unless you choose other qualities in /jd options.",
  "Usage: /junkdrop or /jd, followed by any of these options:",
  "  (nothing) - delete the next stack in line.",
  "  <number> - delete that many stacks, for example /jd 3.",
  "  all - delete every stack that qualifies. Cannot be combined with a number.",
  "  list - delete nothing; show the next stack in line. Use it to decide whether a new item is worth looting.",
  "  list <number> or list all - show that many stacks, or every stack, in drop order.",
  "  debug - show every stack found, in drop order, and mark the ones that are or would be dropped.",
  "  options - open the settings window (also: right-click the LDB item).",
  "  help - show this text.",
  "Options can be combined, for example /jd list 3 or /jd 3 debug.",
  "A stack is one bag slot, and its value is the vendor price of the whole stack.",
}

local function ShowHelp()
  for _, Line in ipairs(HelpLines) do
    Say(Line)
  end
end

local QuestClassID = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12

-- Whether an item may be dropped under the current settings. Anything better than Poor must
-- also have a vendor price and not be a quest item. That keeps things like the Hearthstone,
-- which sells for nothing, from looking like the cheapest item in the bags.
local function IsCandidate(Quality, SellPrice, ClassID)
  if not Quality or not JD.Get("Include" .. Quality) then
    return false
  end
  if Quality == 0 then
    return true
  end
  return SellPrice > 0 and ClassID ~= QuestClassID
end

-- Every stack in the bags that may be dropped, in the order they would be dropped. The order is
-- lowest quality first or cheapest first, per the settings, and a stack's value is the vendor
-- price of the whole stack. Shared by the slash command and the LDB display, which still call
-- these "junk" stacks even when the settings let in better qualities.
local function GetJunkStacks()
  local JunkStacks = {}
  for Bag = 0, LastBag do
    for Slot = 1, GetContainerNumSlots(Bag) do
      local ItemLink = GetContainerItemLink(Bag, Slot)
      if ItemLink then
        local Name, _, Quality, _, _, _, _, _, _, _, SellPrice, ClassID = GetItemInfo(ItemLink)
        if IsCandidate(Quality, SellPrice, ClassID) then
          local ItemCount = GetStackCount(Bag, Slot)
          tinsert(JunkStacks, {
            Link = ItemLink,
            Name = Name,
            Quality = Quality,
            Bag = Bag,
            Slot = Slot,
            Count = ItemCount,
            Value = SellPrice * ItemCount,
            Order = #JunkStacks + 1, -- Scan order breaks ties; table.sort is not stable.
          })
        end
      end
    end
  end

  local ByPrice = JD.Get("Order") == "price"
  table.sort(JunkStacks, function(A, B)
    if not ByPrice and A.Quality ~= B.Quality then
      return A.Quality < B.Quality
    end
    if A.Value ~= B.Value then
      return A.Value < B.Value
    end
    if A.Quality ~= B.Quality then
      return A.Quality < B.Quality
    end
    return A.Order < B.Order
  end)

  return JunkStacks
end

-- Delete the given stacks. A slot is skipped if it no longer holds the item it held when the
-- stacks were ranked, which matters when the deletion waits on a confirmation window.
local function DeleteStacks(Stacks, Report)
  for _, Stack in ipairs(Stacks) do
    if GetContainerItemLink(Stack.Bag, Stack.Slot) == Stack.Link then
      PickupContainerItem(Stack.Bag, Stack.Slot)
      DeleteCursorItem()
      if Report then
        Say("Deleted " .. Stack.Link .. " x " .. Stack.Count .. " @ " .. FormatCoins(Stack.Value))
      end
    end
  end
end

StaticPopupDialogs["JUNKDROP_CONFIRM_RUN"] = {
  text = "JunkDrop will delete:\n%s\nThis cannot be undone.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, Stacks)
    DeleteStacks(Stacks, JD.Get("ReportDrops"))
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- The LDB file is loaded after this one and shares these through the addon table.
JD.GetJunkStacks = GetJunkStacks
JD.FormatCoins = FormatCoins

function JunkDrop(SlashArg)
  local DebugOn = false
  local DropAll = false
  local ListOnly = false -- Report what a normal run would drop without deleting anything.
  local CountToDrop = 1
  local CountGiven = false

  for Argument in string.gmatch(string.lower(SlashArg or ""), "[^ ]+") do
    if Argument == "debug" then
      DebugOn = true
    elseif Argument == "list" then
      ListOnly = true
    elseif Argument == "all" then
      DropAll = true
    elseif Argument == "options" then
      JD.OpenOptions()
      return
    elseif Argument == "help" or Argument == "?" then
      ShowHelp()
      return
    elseif string.find(Argument, "^%d+$") then
      CountToDrop = tonumber(Argument)
      CountGiven = true
      if CountToDrop < 1 then
        Say("The number of stacks to drop must be 1 or more. Type /jd help for usage.")
        return
      end
    else
      -- Unknown argument: stop rather than guess and delete something.
      Say("Unknown option '" .. Argument .. "'. Type /jd help for usage.")
      return
    end
  end

  if DropAll and CountGiven then
    Say("'all' and a number cannot be combined. Type /jd help for usage.")
    return
  end

  local JunkStacks = GetJunkStacks()
  local DropTotal = DropAll and #JunkStacks or math.min(CountToDrop, #JunkStacks)

  if DebugOn or ListOnly then
    if #JunkStacks == 0 then
      Say("We didn't find anything to drop.")
    elseif ListOnly and not DebugOn and DropTotal == 1 then
      -- The common farming check: one line to compare a new item against.
      local Stack = JunkStacks[1]
      Say("Next to drop: " .. Stack.Link .. " x " .. Stack.Count .. " @ " .. FormatCoins(Stack.Value))
    else
      -- Debug shows every stack so the selection can be checked; list shows only the selection.
      local Shown = DebugOn and #JunkStacks or DropTotal
      if DebugOn then
        Say("Found " .. #JunkStacks .. " stack(s), in drop order:")
      elseif DropAll then
        Say("All " .. #JunkStacks .. " stack(s), in drop order:")
      else
        Say("The next " .. DropTotal .. " stack(s) to drop:")
      end
      for Rank = 1, Shown do
        local Stack = JunkStacks[Rank]
        local Marker = ""
        if DebugOn and Rank <= DropTotal then
          Marker = ListOnly and " <-- would drop" or " <-- dropping"
        end
        Say(Rank .. ". " .. Stack.Link .. " x " .. Stack.Count .. " @ " .. FormatCoins(Stack.Value) .. Marker)
      end
    end
  end

  if not ListOnly then
    local Targets = {}
    local HasBetterThanPoor = false
    for Rank = 1, DropTotal do
      tinsert(Targets, JunkStacks[Rank])
      if JunkStacks[Rank].Quality > 0 then
        HasBetterThanPoor = true
      end
    end

    if HasBetterThanPoor and JD.Get("ConfirmHigher") then
      -- Show exactly what will go, and delete exactly that if the player agrees.
      local Lines = {}
      for Rank = 1, math.min(#Targets, 6) do
        tinsert(Lines, Targets[Rank].Link .. " x" .. Targets[Rank].Count)
      end
      if #Targets > 6 then
        tinsert(Lines, "...and " .. (#Targets - 6) .. " more")
      end
      StaticPopup_Show("JUNKDROP_CONFIRM_RUN", table.concat(Lines, "\n"), nil, Targets)
    else
      DeleteStacks(Targets, JD.Get("ReportDrops") and not DebugOn) -- Debug already lists what is dropped.
    end
  end
end

SLASH_JUNKDROP1, SLASH_JUNKDROP2 = '/junkdrop', '/jd';
SlashCmdList["JUNKDROP"] = JunkDrop;
