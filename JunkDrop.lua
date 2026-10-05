-- JunkDrop.lua
-- by: desertdwarf
-- Version: v0.8
-- Released: 2012-09-11T03:27:01Z

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
  "Deletes your cheapest junk (grey) items. It does not sell them.",
  "Usage: /junkdrop or /jd, followed by any of these options:",
  "  (nothing) - delete the single cheapest junk stack.",
  "  <number> - delete that many of the cheapest junk stacks, for example /jd 3.",
  "  all - delete every junk item. Cannot be combined with a number.",
  "  list - delete nothing; show the cheapest junk stack. Use it to decide whether a new grey is worth looting.",
  "  list <number> or list all - show that many of the cheapest stacks, or every junk stack.",
  "  debug - show every junk stack found, cheapest first, and mark the ones that are or would be dropped.",
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

-- Every junk (grey) stack in the bags, ranked by the vendor value of the whole stack,
-- cheapest first. Shared by the slash command and the LDB display.
local function GetJunkStacks()
  local JunkStacks = {}
  for Bag = 0, LastBag do
    for Slot = 1, GetContainerNumSlots(Bag) do
      local ItemLink = GetContainerItemLink(Bag, Slot)
      if ItemLink then
        local Name, _, Quality, _, _, _, _, _, _, _, SellPrice = GetItemInfo(ItemLink)
        if Quality == 0 then -- is grey?
          local ItemCount = GetStackCount(Bag, Slot)
          tinsert(JunkStacks, {
            Link = ItemLink,
            Name = Name,
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

  table.sort(JunkStacks, function(A, B)
    if A.Value ~= B.Value then
      return A.Value < B.Value
    end
    return A.Order < B.Order
  end)

  return JunkStacks
end

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
      Say("We didn't find any junk.")
    elseif ListOnly and not DebugOn and DropTotal == 1 then
      -- The common farming check: one line to compare a new grey against.
      local Stack = JunkStacks[1]
      Say("Cheapest junk stack: " .. Stack.Link .. " x " .. Stack.Count .. " @ " .. FormatCoins(Stack.Value))
    else
      -- Debug shows every stack so the selection can be checked; list shows only the selection.
      local Shown = DebugOn and #JunkStacks or DropTotal
      if DebugOn then
        Say("Found " .. #JunkStacks .. " junk stack(s), cheapest first:")
      elseif DropAll then
        Say("All " .. #JunkStacks .. " junk stack(s), cheapest first:")
      else
        Say("The " .. DropTotal .. " cheapest junk stack(s):")
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
    for Rank = 1, DropTotal do
      PickupContainerItem(JunkStacks[Rank].Bag, JunkStacks[Rank].Slot)
      DeleteCursorItem()
      if JD.Get("ReportDrops") and not DebugOn then -- Debug already lists what is dropped.
        local Stack = JunkStacks[Rank]
        Say("Deleted " .. Stack.Link .. " x " .. Stack.Count .. " @ " .. FormatCoins(Stack.Value))
      end
    end
  end
end

SLASH_JUNKDROP1, SLASH_JUNKDROP2 = '/junkdrop', '/jd';
SlashCmdList["JUNKDROP"] = JunkDrop;
