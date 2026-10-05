-- JunkDrop.lua
-- by: desertdwarf
-- Version: v0.8
-- Released: 2012-09-11T03:27:01Z

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
-- Formats a copper amount as gold/silver/copper coin icons for chat output.
local GetCoinTextureString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString

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
  "  help - show this text.",
  "Options can be combined, for example /jd list 3 or /jd 3 debug.",
  "A stack is one bag slot, and its value is the vendor price of the whole stack.",
}

local function ShowHelp()
  for _, Line in ipairs(HelpLines) do
    Say(Line)
  end
end

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

  -- Collect every junk stack, then rank by the value of the whole stack.
  local JunkStacks = {}
  for Bag = 0, LastBag do
    for Slot = 1, GetContainerNumSlots(Bag) do
      local ItemLink = GetContainerItemLink(Bag, Slot)
      if ItemLink and select(3, GetItemInfo(ItemLink)) == 0 then -- is grey?
        local ItemCount = GetStackCount(Bag, Slot)
        tinsert(JunkStacks, {
          Link = ItemLink,
          Bag = Bag,
          Slot = Slot,
          Count = ItemCount,
          Value = select(11, GetItemInfo(ItemLink)) * ItemCount,
          Order = #JunkStacks + 1, -- Scan order breaks ties; table.sort is not stable.
        })
      end
    end
  end

  table.sort(JunkStacks, function(A, B)
    if A.Value ~= B.Value then
      return A.Value < B.Value
    end
    return A.Order < B.Order
  end)

  local DropTotal = DropAll and #JunkStacks or math.min(CountToDrop, #JunkStacks)

  if DebugOn or ListOnly then
    if #JunkStacks == 0 then
      Say("We didn't find any junk.")
    elseif ListOnly and not DebugOn and DropTotal == 1 then
      -- The common farming check: one line to compare a new grey against.
      local Stack = JunkStacks[1]
      Say("Cheapest junk stack: " .. Stack.Link .. " x " .. Stack.Count .. " @ " .. GetCoinTextureString(Stack.Value))
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
        Say(Rank .. ". " .. Stack.Link .. " x " .. Stack.Count .. " @ " .. GetCoinTextureString(Stack.Value) .. Marker)
      end
    end
  end

  if not ListOnly then
    for Rank = 1, DropTotal do
      PickupContainerItem(JunkStacks[Rank].Bag, JunkStacks[Rank].Slot)
      DeleteCursorItem()
    end
  end
end

SLASH_JUNKDROP1, SLASH_JUNKDROP2 = '/junkdrop', '/jd';
SlashCmdList["JUNKDROP"] = JunkDrop;
