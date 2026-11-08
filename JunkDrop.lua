-- JunkDrop.lua
-- by: desertdwarf

local _, JD = ... -- Addon name and the table shared between this addon's files.

-- Container/item APIs moved into C_Container/C_Item in modern clients and the old
-- globals are gone there. Bind locals so call sites below work on either API.
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
local GetContainerItemQuestInfo = C_Container and C_Container.GetContainerItemQuestInfo or GetContainerItemQuestInfo
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
  Dots = true, -- Show a colored dot per selected item quality after the label on LDB displays.
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
  Protect = "", -- Comma-separated words; an item whose name contains one is never dropped.
  Glow = true, -- Pulse a red glow around the next stack to drop when the bags are open.
  LootNote = true, -- Beside the loot window, say whether to take each item that won't fit.
  LootDrop = true, -- Put a button on that note that drops the stacks it suggests.
  AckDrop = false, -- Set once the player has accepted the one-time warning before a bar click or /jd deletes.
  AckAll = false, -- The same for "/jd all". Neither is in the options window; Reset to defaults clears them.
}

local function SettingsChanged()
  if JD.RefreshText then
    JD.RefreshText()
  end
  if JD.RefreshGlow then
    JD.RefreshGlow()
  end
  if JD.RefreshLoot then
    JD.RefreshLoot()
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
  if JD.SyncOptions then
    JD.SyncOptions() -- An open options window should show the defaults again.
  end
end

-- Resetting clears every setting, including the player's Never drop words and the one-time
-- warnings, so it always asks first. The Reset to defaults button and /jd reset both come here.
StaticPopupDialogs["JUNKDROP_CONFIRM_RESET"] = {
  text = "Reset all JunkDrop settings to their defaults?\n\n"
    .. "This also clears your Never drop words and brings the one-time warnings back.",
  button1 = "Reset",
  button2 = CANCEL,
  OnAccept = function()
    JD.Reset()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

function JD.ConfirmReset()
  StaticPopup_Show("JUNKDROP_CONFIRM_RESET")
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

-- EllesmereUI themes other addons' windows through its skinning hook, which accepts only one
-- registration per addon name. So there is one registration here, and each window of ours asks to
-- be told when the skin is ready: JD.OnSkin(Fn) calls Fn(S) now if it already is, and whenever it
-- becomes ready. Without EllesmereUI (or with skinning turned off) nothing is ever called.
local SkinCallbacks = {}

function JD.OnSkin(Fn)
  tinsert(SkinCallbacks, Fn)
  if JD.Skin then
    Fn(JD.Skin)
  end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
  EllesmereUI.RegisterSkin("JunkDrop", function(S)
    JD.Skin = S
    for _, Fn in ipairs(SkinCallbacks) do
      Fn(S)
    end
  end)
end

-- Retail added a reagent bag after the four regular bags; older clients stop at NUM_BAG_SLOTS.
local LastBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or NUM_BAG_SLOTS

local function Say(Message)
  ChatFrame1:AddMessage("JunkDrop: " .. Message, .69, .49, 1.0)
end

local HelpLines = {
  "Deletes the lowest-value items in your bags. It does not sell them.",
  "Only Poor (grey) items are considered unless you choose other qualities in /jd options.",
  "Items whose names match the Never drop words in /jd options are always skipped.",
  "Usage: /junkdrop or /jd, followed by any of these options:",
  "  (nothing) - delete the next stack in line.",
  "  <number> - delete that many stacks, for example /jd 3.",
  "  all - delete every stack that qualifies. Cannot be combined with a number.",
  "  list - delete nothing; show the next stack in line. Use it to decide whether a new item is worth looting.",
  "  list <number> or list all - show that many stacks, or every stack, in drop order.",
  "  debug - show every stack found, in drop order, and mark the ones that are or would be dropped.",
  "  options - open the settings window (also: right-click the LDB item).",
  "  reset - reset every setting to its default (asks first).",
  "  help - show this text.",
  "Options can be combined, for example /jd list 3 or /jd 3 debug.",
  "A stack is one bag slot, and its value is the vendor price of the whole stack.",
}

local function ShowHelp()
  for _, Line in ipairs(HelpLines) do
    Say(Line)
  end
end

-- Calls Visit(Bag, Slot, ItemLink) for every item in the bags.
local function ForEachBagItem(Visit)
  for Bag = 0, LastBag do
    for Slot = 1, GetContainerNumSlots(Bag) do
      local ItemLink = GetContainerItemLink(Bag, Slot)
      if ItemLink then
        Visit(Bag, Slot, ItemLink)
      end
    end
  end
end

-- Split the "never drop" setting into lowercase words. Commas separate the words.
local function ParseTerms(Text)
  local Terms = {}
  for Raw in string.gmatch(Text or "", "[^,]+") do
    local Term = string.match(Raw, "^%s*(.-)%s*$")
    if Term ~= "" then
      tinsert(Terms, string.lower(Term))
    end
  end
  return Terms
end

-- Whether any word appears anywhere in the item's name, ignoring case.
local function MatchesTerms(Name, Terms)
  if not Name then
    return false
  end
  local Lower = string.lower(Name)
  for _, Term in ipairs(Terms) do
    if string.find(Lower, Term, 1, true) then -- Plain text, not a pattern.
      return true
    end
  end
  return false
end

local QuestClassID = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12

-- Whether the game's quest info for a bag slot marks it as a quest item: needed for a quest, or
-- starting one. The modern API returns a table ({ isQuestItem, questID, isActive }); the old
-- global returns the same things as separate values.
local function IsQuestFlag(First, Second)
  if type(First) == "table" then
    return First.isQuestItem == true or (First.questID or 0) ~= 0
  end
  return First == true or (Second or 0) ~= 0
end

-- A quest item is one of the Quest class, or one the game flags as part of a quest. Items for
-- quests sit in other classes too, so the flag is checked as well as the class.
local function IsQuestItem(Bag, Slot, ClassID)
  if ClassID == QuestClassID then
    return true
  end
  return GetContainerItemQuestInfo ~= nil and IsQuestFlag(GetContainerItemQuestInfo(Bag, Slot))
end

-- Whether an item may be dropped under the current settings. A quest item never is, at any
-- quality. Anything better than Poor must also have a vendor price, which keeps things like the
-- Hearthstone, which sells for nothing, from looking like the cheapest item in the bags.
local function IsCandidate(Quality, SellPrice, ClassID, Bag, Slot)
  if not Quality or not JD.Get("Include" .. Quality) then
    return false
  end
  if Quality > 0 and not (SellPrice > 0) then
    return false
  end
  return not IsQuestItem(Bag, Slot, ClassID) -- Last, as it asks the game about this slot.
end

-- Every stack in the bags that may be dropped, in the order they would be dropped. The order is
-- lowest quality first or cheapest first, per the settings, and a stack's value is the vendor
-- price of the whole stack. Shared by the slash command and the LDB display, which still call
-- these "junk" stacks even when the settings let in better qualities.
local function GetJunkStacks()
  local JunkStacks = {}
  local Protected = ParseTerms(JD.Get("Protect"))
  ForEachBagItem(function(Bag, Slot, ItemLink)
    local Name, _, Quality, _, _, _, _, _, _, Icon, SellPrice, ClassID = GetItemInfo(ItemLink)
    if IsCandidate(Quality, SellPrice, ClassID, Bag, Slot) and not MatchesTerms(Name, Protected) then
      local ItemCount = GetStackCount(Bag, Slot)
      tinsert(JunkStacks, {
        Link = ItemLink,
        Name = Name,
        Icon = Icon,
        Quality = Quality,
        Bag = Bag,
        Slot = Slot,
        Count = ItemCount,
        Value = SellPrice * ItemCount,
        Order = #JunkStacks + 1, -- Scan order breaks ties; table.sort is not stable.
      })
    end
  end)

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

-- Print which items in the bags a "never drop" filter matches, for the options window's Test
-- button. Each match says whether the filter is actually keeping it from being dropped.
local function TestFilter(Text)
  local Terms = ParseTerms(Text)
  if #Terms == 0 then
    Say("Type one or more words, separated by commas, and then press Test.")
    return
  end

  local Matches = {}
  ForEachBagItem(function(Bag, Slot, ItemLink)
    local Name, _, Quality, _, _, _, _, _, _, _, SellPrice, ClassID = GetItemInfo(ItemLink)
    if MatchesTerms(Name, Terms) then
      tinsert(Matches, {
        Link = ItemLink,
        Count = GetStackCount(Bag, Slot),
        WouldDrop = IsCandidate(Quality, SellPrice, ClassID, Bag, Slot),
      })
    end
  end)

  if #Matches == 0 then
    Say("'" .. table.concat(Terms, ", ") .. "' matches nothing in your bags right now.")
    return
  end
  Say("'" .. table.concat(Terms, ", ") .. "' matches " .. #Matches .. " stack(s) in your bags:")
  for Rank = 1, math.min(#Matches, 10) do
    local Match = Matches[Rank]
    local Note = Match.WouldDrop and "kept safe (it would otherwise be dropped)" or "not on the drop list anyway"
    Say("  " .. Match.Link .. " x" .. Match.Count .. " - " .. Note)
  end
  if #Matches > 10 then
    Say("  ...and " .. (#Matches - 10) .. " more")
  end
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

-- A short list of what is about to be deleted, for the pop-ups.
local function ListStacks(Targets)
  local Lines = {}
  for Rank = 1, math.min(#Targets, 6) do
    tinsert(Lines, Targets[Rank].Link .. " x" .. Targets[Rank].Count)
  end
  if #Targets > 6 then
    tinsert(Lines, "...and " .. (#Targets - 6) .. " more")
  end
  return table.concat(Lines, "\n")
end

-- The one-time warnings. Each is shown the first time a delete would otherwise happen with no
-- question asked, and Key is the saved setting that remembers the player accepted it. These are
-- standard pop-ups, so they look like Blizzard's, or follow the player's EllesmereUI theme.
-- DropAck covers an ordinary drop, whether it comes from a click on the bar item or a typed /jd,
-- so it reads the same either way and accepting it in one place covers the other.
local DropAck = {
  Key = "AckDrop",
  Intro = "JunkDrop deletes items. It does not sell them, and a deleted item cannot be recovered.\n\n"
    .. "Clicking the bar item, or typing /jd, deletes items from your bags, lowest value first. This time:",
  Outro = "Choose I understand to delete now. You won't be warned about this again.",
}
local AllAck = {
  Key = "AckAll",
  Intro = "/jd all deletes every item that qualifies, right now. It does not sell them, and a deleted "
    .. "item cannot be recovered. This time that is:",
  Outro = "Choose I understand to delete them now. You won't be warned about this again.",
}

StaticPopupDialogs["JUNKDROP_ACK"] = {
  text = "%s",
  button1 = "I understand",
  button2 = CANCEL,
  OnAccept = function(_, Data)
    JD.Set(Data.Key, true)
    DeleteStacks(Data.Targets, Data.Report)
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Delete the given stacks. When any is better than Poor and the settings say so, ask first. Failing
-- that, if Ack (one of the warnings above) is given and the player has not accepted it yet, show it
-- instead. Report says whether to print each deleted stack. Shared by the slash command, the bar
-- item and the loot note's button, so they follow the same safeguards.
local function DropStacks(Targets, Report, Ack)
  local HasBetterThanPoor = false
  for _, Stack in ipairs(Targets) do
    if Stack.Quality > 0 then
      HasBetterThanPoor = true
    end
  end

  if HasBetterThanPoor and JD.Get("ConfirmHigher") then
    -- Show exactly what will go, and delete exactly that if the player agrees.
    StaticPopup_Show("JUNKDROP_CONFIRM_RUN", ListStacks(Targets), nil, Targets)
  elseif Ack and #Targets > 0 and not JD.Get(Ack.Key) then
    StaticPopup_Show("JUNKDROP_ACK", Ack.Intro .. "\n\n" .. ListStacks(Targets) .. "\n\n" .. Ack.Outro,
      nil, { Key = Ack.Key, Targets = Targets, Report = Report })
  else
    DeleteStacks(Targets, Report)
  end
end

-- The other files are loaded after this one and share these through the addon table.
JD.GetJunkStacks = GetJunkStacks
JD.TestFilter = TestFilter
JD.FormatCoins = FormatCoins
JD.DropStacks = DropStacks
JD.DropAck = DropAck
JD.IsQuestFlag = IsQuestFlag
JD.ForEachBagItem = ForEachBagItem
JD.GetStackCount = GetStackCount
JD.LastBag = LastBag

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
    elseif Argument == "reset" then
      JD.ConfirmReset()
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
    for Rank = 1, DropTotal do
      tinsert(Targets, JunkStacks[Rank])
    end
    -- Debug already lists what is dropped. A delete with no question asked carries a one-time warning:
    -- the shared one for an ordinary drop, and its own for "all".
    DropStacks(Targets, JD.Get("ReportDrops") and not DebugOn, DropAll and AllAck or DropAck)
  end
end

SLASH_JUNKDROP1, SLASH_JUNKDROP2 = '/junkdrop', '/jd';
SlashCmdList["JUNKDROP"] = JunkDrop;
