local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
ldb:NewDataObject("JunkDrop-LDB", {
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
		tooltip:AddLine("JunkDrop-LDB")
		tooltip:AddLine("Click to drop (delete) a single item (or stack) of junk.")
	end,
})
