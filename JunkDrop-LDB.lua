local _, JD = ... -- Addon name and the table shared between this addon's files.

local ldb = LibStub:GetLibrary("LibDataBroker-1.1")

local Labels = { full = "JunkDrop", short = "JD", none = "" }

-- The cheapest stack as shown on the bar, following the display settings.
local function StackText(Stack)
	local Show = JD.Get("Show")
	local Parts = {}
	if Show ~= "value" then
		local Name = Stack.Name
		if Stack.Count > 1 and JD.Get("ShowCount") then
			Name = Name .. " x" .. Stack.Count
		end
		tinsert(Parts, Name)
	end
	if Show ~= "name" then
		tinsert(Parts, JD.FormatCoins(Stack.Value))
	end
	return table.concat(Parts, " ")
end

-- Join the label and the body, leaving out the separator when the label is hidden.
local function WithLabel(Body)
	local Label = Labels[JD.Get("Label")] or Labels.full
	if Label == "" then
		return Body
	end
	return Label .. ": " .. Body
end

StaticPopupDialogs["JUNKDROP_CONFIRM"] = {
	text = "Delete %s?\nThis cannot be undone.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		JunkDrop()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local broker = ldb:NewDataObject("JunkDrop-LDB", {
	type = "launcher",
	text = "JunkDrop",
	icon = "Interface\\AddOns\\JunkDrop\\JunkDrop-LDB-icon",
	OnClick = function(_, msg)
		if msg == "LeftButton" then -- Left mouse button to call JunkDrop
			local Stack = JD.GetJunkStacks()[1]
			if Stack and JD.Get("ConfirmClick") then
				StaticPopup_Show("JUNKDROP_CONFIRM", Stack.Link .. " x" .. Stack.Count .. " (" .. JD.FormatCoins(Stack.Value) .. ")")
			else
				JunkDrop()
			end
		elseif msg == "RightButton" then
			JD.OpenOptions()
		end
	end,
	OnTooltipShow = function(tooltip)
		if not tooltip or not tooltip.AddLine then
			return
		end
		local JunkStacks = JD.GetJunkStacks()
		local Rows = JD.Get("TooltipRows")
		tooltip:AddLine("JunkDrop")
		if #JunkStacks == 0 then
			tooltip:AddLine("No junk in your bags.", 1, 1, 1)
		else
			tooltip:AddLine("Cheapest junk stacks:", 1, 1, 1)
			for Rank = 1, math.min(Rows, #JunkStacks) do
				local Stack = JunkStacks[Rank]
				local Name = Stack.Link
				if Stack.Count > 1 then
					Name = Name .. " x" .. Stack.Count
				end
				tooltip:AddDoubleLine(Name, JD.FormatCoins(Stack.Value), 1, 1, 1, 1, 1, 1)
			end
			if #JunkStacks > Rows then
				tooltip:AddLine("...and " .. (#JunkStacks - Rows) .. " more", .6, .6, .6)
			end
		end
		tooltip:AddLine(" ")
		tooltip:AddLine("Left-click: delete the cheapest junk stack. This cannot be undone.", 0, 1, 0, true)
		tooltip:AddLine("Right-click: options. Type /jd help for commands.", .6, .6, .6)
	end,
})

-- Show the cheapest junk stack next to the name on LDB displays.
function JD.RefreshText()
	local Stack = JD.GetJunkStacks()[1]
	broker.text = WithLabel(Stack and StackText(Stack) or "no junk")
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
		JD.RefreshText()
	end)
end

local Events = CreateFrame("Frame")
Events:RegisterEvent("PLAYER_ENTERING_WORLD")
Events:RegisterEvent("BAG_UPDATE_DELAYED")
Events:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- Item names/prices may not be cached at login.
Events:SetScript("OnEvent", QueueRefresh)
