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
local GetCoinTextureString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString

-- Total vendor value of a stack as gold/silver/copper coin icons, for chat output.
local function FormatValue(ItemLink, ItemCount)
  return GetCoinTextureString(select(11, GetItemInfo(ItemLink)) * ItemCount)
end

-- Retail added a reagent bag after the four regular bags; older clients stop at NUM_BAG_SLOTS.
local LastBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or NUM_BAG_SLOTS

function JunkDrop(SlashArg)
  local EmergencyBreak = 9999 -- Prevent run-away train situation.
  local ItemLinkLowest
  local ItemLinkLowestBag
  local ItemLinkLowestSlot
  local ItemCountLowest
  local ItemLink
  local ItemLinkBag
  local ItemLinkSlot
  local ItemCount
  local CommandLine = {}
  local SlashArgValue
  local DebugOn = false
  local DropAll = false
  local DryRun = false -- Report what would be dropped without deleting anything.
  local DropVerb = "Dropping"
  local CountToDrop
  local index
  local argument
  local bag
  local slot

  if SlashArg then

  for SlashArgValue in string.gmatch(SlashArg, "[^ ]+") do
    tinsert(CommandLine, SlashArgValue)
  end

--    ChatFrame1:AddMessage("JunkDrop: SlashArg - " .. SlashArg, .69, .49, 1.0)
    for index,argument in pairs(CommandLine) do
--      ChatFrame1:AddMessage("JunkDrop: SlashArg Loop @ " .. index .. ": " .. argument, .69, .49, 1.0)
      if argument == "debug" then
        DebugOn = true
      elseif argument == "dry" then
        DryRun = true
        DebugOn = true -- A dry run is only useful if it reports what it found.
        DropVerb = "Would drop"
      elseif argument == "all" then
        DropAll = true
      elseif string.len(argument) then
        CountToDrop = tonumber(argument)
        if CountToDrop ~= nil then
          ChatFrame1:AddMessage("JunkDrop: When this option works, I'll throw away " .. CountToDrop .. " items.", .69, .49, 1.0)
        else
          if string.len(argument) > 0 then
            ChatFrame1:AddMessage("JunkDrop: Command usage is /junkdrop [all] [debug] [dry] [#] -- where # is how many items to drop (not yet implemented). Found '" .. argument .. "'.", .69, .49, 1.0)
            return -- Unknown argument: stop rather than guess and delete something.
          end
        end
      end
    end
  end

  if DebugOn and DropAll then
    ChatFrame1:AddMessage("JunkDrop: " .. DropVerb .. " all junk items!", .69, .49, 1.0)
  end

  for bag = 0,LastBag do -- for bags loop
    for slot = 1,GetContainerNumSlots(bag) do -- for slots loop
      ItemLink = GetContainerItemLink(bag, slot)
      if ItemLink and select(3, GetItemInfo(ItemLink)) == 0 then -- is grey?
        if DropAll then -- if all?
          if DebugOn then -- if debug?
            ChatFrame1:AddMessage("JunkDrop: " .. DropVerb .. " " .. ItemLink .. ".", .69, .49, 1.0)
          end -- if debug?
          if not DryRun then PickupContainerItem(bag, slot) end
          if not DryRun then DeleteCursorItem() end
        else -- if all?
          ItemCount = GetStackCount(bag, slot)
          if ItemLinkLowest then -- if lowest price item exists?
            if (select(11, GetItemInfo(ItemLink)) * ItemCount) < (select(11, GetItemInfo(ItemLinkLowest)) * ItemCountLowest) then -- if new item is lower price?
              if DebugOn then -- if debug?
                ChatFrame1:AddMessage("JunkDrop: " .. ItemLinkLowest .. " x " .. ItemCountLowest .. " @ " .. FormatValue(ItemLinkLowest, ItemCountLowest) .. " > " .. ItemLink .. " x " .. ItemCount .. " @ " .. FormatValue(ItemLink, ItemCount) .. ".", .69, .49, 1.0)
              end -- if debug?
              ItemLinkLowest = ItemLink
              ItemLinkLowestBag = bag
              ItemLinkLowestSlot = slot
              ItemCountLowest = ItemCount
            else -- if new item is lower price?
              if DebugOn then -- if debug?
                ChatFrame1:AddMessage("JunkDrop: " .. ItemLinkLowest .. " x " .. ItemCountLowest .. " @ " .. FormatValue(ItemLinkLowest, ItemCountLowest) .. " <= " .. ItemLink .. " x " .. ItemCount .. " @ " .. FormatValue(ItemLink, ItemCount) .. ".", .69, .49, 1.0)
              end -- if debug?
            end -- if new item is lower?
          else -- if lowest price item exists?
              if DebugOn then -- if debug?
                ChatFrame1:AddMessage("JunkDrop: ---", .69, .49, 1.0)
                ChatFrame1:AddMessage("JunkDrop: We found our first junk item: " .. ItemLink .. " x " .. ItemCount .. " @ " .. FormatValue(ItemLink, ItemCount) .. ".", .69, .49, 1.0)
              end -- if debug?
              ItemLinkLowest = ItemLink
              ItemLinkLowestBag = bag
              ItemLinkLowestSlot = slot
              ItemCountLowest = ItemCount
          end -- if lowest price item exists?
        end -- if all?
        EmergencyBreak = EmergencyBreak - 1
        if EmergencyBreak == 0 then -- if emergencybreak for slots loop
          ChatFrame1:AddMessage("JunkDrop: Emergency break applied. (Pun intended.) Report this to DesertDwarf on CurseForge.com on the JunkDrop addon page.", .69, .49, 1.0)
          break
        end -- if emergencybreak for slots loop
      end -- if grey
    end -- for slots loop
    if EmergencyBreak == 0 then -- if emergencybreak for bags loop
      ChatFrame1:AddMessage("JunkDrop: Emergency break applied. (Pun intended.) Report this to DesertDwarf on CurseForge.com on the JunkDrop addon page.", .69, .49, 1.0)
      break
    end -- if emergencybreak for bags loop
  end -- for bags loop
  
  if ItemLinkLowest and not DropAll then
    if DebugOn then
      ChatFrame1:AddMessage("JunkDrop: " .. DropVerb .. " " .. ItemLinkLowest .. " x " .. ItemCountLowest .. " @ " .. FormatValue(ItemLinkLowest, ItemCountLowest) .. ".", .69, .49, 1.0)
    end
    if not DryRun then PickupContainerItem(ItemLinkLowestBag, ItemLinkLowestSlot) end
    if not DryRun then DeleteCursorItem() end
  else
    if DebugOn then
      if DropAll then
        ChatFrame1:AddMessage("JunkDrop: Done!", .69, .49, 1.0)
      else
        ChatFrame1:AddMessage("JunkDrop: We didn't find any junk.", .69, .49, 1.0)
      end
    end
  end
end

SLASH_JUNKDROP1, SLASH_JUNKDROP2 = '/junkdrop', '/jd';
SlashCmdList["JUNKDROP"] = JunkDrop;
