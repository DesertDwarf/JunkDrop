local _, JD = ... -- Addon name and the table shared between this addon's files.

local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local TooltipRows = 5 -- How many of the cheapest stacks the hover tooltip lists.

local function StackText(Stack)
	local Text = Stack.Name
	if Stack.Count > 1 then
		Text = Text .. " x" .. Stack.Count
	end
	return Text .. " " .. JD.FormatCoins(Stack.Value)
end

local broker = ldb:NewDataObject("JunkDrop-LDB", {
	type = "launcher",
	text = "JunkDrop",
	icon = "Interface\\AddOns\\JunkDrop\\JunkDrop-LDB-icon",
	OnClick = function(_, msg)
		if msg == "LeftButton" then -- Left mouse button to call JunkDrop
			JunkDrop()
		end
	end,
	OnTooltipShow = function(tooltip)
		if not tooltip or not tooltip.AddLine then
			return
		end
		local JunkStacks = JD.GetJunkStacks()
		tooltip:AddLine("JunkDrop")
		if #JunkStacks == 0 then
			tooltip:AddLine("No junk in your bags.", 1, 1, 1)
		else
			tooltip:AddLine("Cheapest junk stacks:", 1, 1, 1)
			for Rank = 1, math.min(TooltipRows, #JunkStacks) do
				local Stack = JunkStacks[Rank]
				local Name = Stack.Link
				if Stack.Count > 1 then
					Name = Name .. " x" .. Stack.Count
				end
				tooltip:AddDoubleLine(Name, JD.FormatCoins(Stack.Value), 1, 1, 1, 1, 1, 1)
			end
			if #JunkStacks > TooltipRows then
				tooltip:AddLine("...and " .. (#JunkStacks - TooltipRows) .. " more", .6, .6, .6)
			end
		end
		tooltip:AddLine(" ")
		tooltip:AddLine("Left-click: delete the cheapest junk stack. This cannot be undone.", 0, 1, 0, true)
		tooltip:AddLine("Type /jd help for more options.", .6, .6, .6)
	end,
})

-- Show the cheapest junk stack next to the name on LDB displays.
local function RefreshText()
	local Stack = JD.GetJunkStacks()[1]
	broker.text = Stack and ("JunkDrop: " .. StackText(Stack)) or "JunkDrop: no junk"
end

-- Bag and item-cache events arrive in bursts, so coalesce them into one scan.
local RefreshPending = false
local function QueueRefresh()
	if RefreshPending then
		return
	end
	RefreshPending = true
	C_Timer.After(0.3, function()
		RefreshPending = false
		RefreshText()
	end)
end

local Events = CreateFrame("Frame")
Events:RegisterEvent("PLAYER_ENTERING_WORLD")
Events:RegisterEvent("BAG_UPDATE_DELAYED")
Events:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- Item names/prices may not be cached at login.
Events:SetScript("OnEvent", QueueRefresh)
