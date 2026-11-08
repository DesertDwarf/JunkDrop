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

-- One small dot per selected quality, in the quality's color. These are inline textures rather
-- than colored text, so a display that strips color codes (EllesmereUI does by default) keeps them.
local function QualityDots()
	local Dots = ""
	for Quality = 0, 4 do
		if JD.Get("Include" .. Quality) then
			Dots = Dots .. "|TInterface\\AddOns\\JunkDrop\\JunkDrop-Dot" .. Quality .. ":0|t"
		end
	end
	return Dots
end

-- Put the label and the quality dots in front of the body. The dots show even when the label is hidden.
local function WithLabel(Body)
	local Label = Labels[JD.Get("Label")] or Labels.full
	local Dots = JD.Get("Dots") and QualityDots() or ""
	if Label == "" then
		return Dots == "" and Body or (Dots .. " " .. Body)
	end
	if Dots ~= "" then
		Label = Label .. " " .. Dots
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
	type = "data source", -- It shows live text, and some displays (ElvUI) only show the text of a data source by default.
	text = "JunkDrop",
	icon = "Interface\\AddOns\\JunkDrop\\JunkDrop-LDB-icon",
	OnClick = function(_, msg)
		if msg == "LeftButton" then -- Left mouse button to call JunkDrop
			local Stack = JD.GetJunkStacks()[1]
			-- Anything better than Poor is confirmed by JunkDrop() itself, so only ask here for Poor.
			if Stack and Stack.Quality == 0 and JD.Get("ConfirmClick") then
				StaticPopup_Show("JUNKDROP_CONFIRM", Stack.Link .. " x" .. Stack.Count .. " (" .. JD.FormatCoins(Stack.Value) .. ")")
			elseif Stack then
				-- The first time, with nothing else asking, a one-time warning comes first.
				JD.DropStacks({ Stack }, JD.Get("ReportDrops"), JD.DropAck)
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
			tooltip:AddLine("Nothing to drop in your bags.", 1, 1, 1)
		else
			tooltip:AddLine("Next to be dropped:", 1, 1, 1)
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
		tooltip:AddLine("Left-click: delete the first stack listed. This cannot be undone.", 0, 1, 0, true)
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
		if JD.RefreshGlow then
			JD.RefreshGlow()
		end
	end)
end

local Events = CreateFrame("Frame")
Events:RegisterEvent("PLAYER_ENTERING_WORLD")
Events:RegisterEvent("BAG_UPDATE_DELAYED")
Events:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- Item names/prices may not be cached at login.
Events:SetScript("OnEvent", QueueRefresh)
