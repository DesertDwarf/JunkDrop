-- Options.lua
-- The settings window: /jd options, or right-click the LDB item.

local _, JD = ... -- Addon name and the table shared between this addon's files.

local Frame -- Created the first time the window is opened.
local Skin -- EllesmereUI's skinning facade, set only when that addon is installed and skinning is on.
local Syncs = {} -- One function per control, each re-reading its setting.

local function SyncAll()
  for _, Sync in ipairs(Syncs) do
    Sync()
  end
end

-- Hand the window to EllesmereUI so it follows the player's chosen theme. EllesmereUI calls
-- the registered function at login, usually before the window exists, so ApplySkin also runs
-- when the window is built.
local function ApplySkinTo(S)
  S.Shell(Frame)
  if Frame.Inset then
    S.Inset(Frame.Inset)
  end
  if Frame.CloseButton then
    S.CloseButton(Frame.CloseButton)
  end
  for _, Button in ipairs(Frame.CheckButtons) do
    S.Checkbox(Button)
  end
  S.Button(Frame.ResetButton)
  S.Button(Frame.TestButton)
  S.EditBox(Frame.FilterBox)
end

local function ApplySkin()
  if not (Skin and Frame) then
    return
  end
  -- EllesmereUI's skin functions are outside code. If one fails, report it through the normal
  -- error handler but still let the window open, just unthemed.
  local Ok, Err = pcall(ApplySkinTo, Skin)
  if not Ok then
    geterrorhandler()(Err)
  end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
  EllesmereUI.RegisterSkin("JunkDrop", function(S)
    Skin = S
    ApplySkin()
  end)
end

local function AddHeader(Text, Y)
  local Header = Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Header:SetPoint("TOPLEFT", 16, Y)
  Header:SetText(Text)
end

local function NewCheckButton(Text, X, Y)
  local Button = CreateFrame("CheckButton", nil, Frame, "UICheckButtonTemplate")
  Button:SetSize(24, 24)
  Button:SetPoint("TOPLEFT", X, Y)
  -- The template's own label is named differently across clients, so draw a label of our own.
  local Label = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  Label:SetPoint("LEFT", Button, "RIGHT", 2, 0)
  Label:SetText(Text)
  tinsert(Frame.CheckButtons, Button)
  return Button
end

-- A single on/off setting. X is the left edge, 16 unless several sit in one row.
local function AddToggle(Key, Text, Y, X)
  local Button = NewCheckButton(Text, X or 16, Y)
  Button:SetScript("OnClick", function(self)
    JD.Set(Key, self:GetChecked() and true or false)
  end)
  tinsert(Syncs, function()
    Button:SetChecked(JD.Get(Key))
  end)
end

-- A pick-one setting drawn as a row of check boxes, so it needs no dropdown template.
-- Step is the distance between choices, 130 unless the labels are long.
local function AddChoice(Key, Title, Choices, Y, Step)
  local TitleText = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  TitleText:SetPoint("TOPLEFT", 16, Y - 5)
  TitleText:SetText(Title)
  for Index, Choice in ipairs(Choices) do
    local Button = NewCheckButton(Choice.Text, 110 + (Index - 1) * (Step or 130), Y)
    Button:SetScript("OnClick", function()
      JD.Set(Key, Choice.Value)
      SyncAll() -- Re-check the row so a click on the chosen option cannot un-check it.
    end)
    tinsert(Syncs, function()
      Button:SetChecked(JD.Get(Key) == Choice.Value)
    end)
  end
end

-- Used only if a client lacks the global quality names.
local QualityFallbackNames = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic" }

local function Build()
  Frame = CreateFrame("Frame", "JunkDropOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
  Frame:SetWidth(520) -- The height is set once the rows are laid out.
  Frame:SetPoint("CENTER")
  Frame:SetFrameStrata("DIALOG")
  Frame:Hide() -- New frames start out visible; OpenOptions decides when to show this one.
  Frame:SetMovable(true)
  Frame:EnableMouse(true)
  Frame:SetClampedToScreen(true)
  Frame:RegisterForDrag("LeftButton")
  Frame:SetScript("OnDragStart", Frame.StartMoving)
  Frame:SetScript("OnDragStop", Frame.StopMovingOrSizing)
  Frame:SetScript("OnShow", SyncAll)
  tinsert(UISpecialFrames, "JunkDropOptionsFrame") -- Close with Escape.
  Frame.CheckButtons = {}

  local Title = Frame.TitleText or Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not Frame.TitleText then
    Title:SetPoint("TOP", 0, -6)
  end
  Title:SetText("JunkDrop Options")

  local Y = -36 -- Each row below sits at Y; Y then moves down by the row's height.

  AddHeader("What can be dropped", Y)
  Y = Y - 22
  for Quality = 0, 4 do
    local Name = _G["ITEM_QUALITY" .. Quality .. "_DESC"] or QualityFallbackNames[Quality]
    local Color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[Quality]
    if Color and type(Color.hex) == "string" and string.sub(Color.hex, 1, 2) == "|c" then
      Name = Color.hex .. Name .. "|r"
    end
    AddToggle("Include" .. Quality, Name, Y, 16 + Quality * 96)
  end
  Y = Y - 30
  AddChoice("Order", "Drop order", {
    { Value = "quality", Text = "Lowest quality first" },
    { Value = "price", Text = "Cheapest price first" },
  }, Y, 190)
  Y = Y - 30
  local Warning = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  Warning:SetPoint("TOPLEFT", 16, Y)
  Warning:SetWidth(488)
  Warning:SetJustifyH("LEFT")
  Warning:SetTextColor(1, .5, .5)
  Warning:SetText("Anything better than Poor is a real item. Items with no vendor price, and quest items, are never picked. Try /jd list first to see what would go.")
  Y = Y - 40

  AddHeader("Never drop", Y)
  Y = Y - 22
  local FilterBox = CreateFrame("EditBox", nil, Frame, "InputBoxTemplate")
  FilterBox:SetSize(370, 22)
  FilterBox:SetPoint("TOPLEFT", 22, Y)
  FilterBox:SetAutoFocus(false)
  FilterBox:SetMaxLetters(255)
  FilterBox:SetScript("OnEnterPressed", FilterBox.ClearFocus)
  FilterBox:SetScript("OnEscapePressed", FilterBox.ClearFocus)
  FilterBox:SetScript("OnEditFocusLost", function(self)
    JD.Set("Protect", self:GetText())
  end)
  tinsert(Syncs, function()
    FilterBox:SetText(JD.Get("Protect"))
  end)
  Frame.FilterBox = FilterBox

  local TestButton = CreateFrame("Button", nil, Frame, "UIPanelButtonTemplate")
  TestButton:SetSize(80, 22)
  TestButton:SetPoint("LEFT", FilterBox, "RIGHT", 10, 0)
  TestButton:SetText("Test")
  TestButton:SetScript("OnClick", function()
    FilterBox:ClearFocus() -- Leaving the box saves what was typed.
    JD.TestFilter(FilterBox:GetText())
  end)
  Frame.TestButton = TestButton
  Y = Y - 28

  local Hint = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  Hint:SetPoint("TOPLEFT", 16, Y)
  Hint:SetWidth(488)
  Hint:SetJustifyH("LEFT")
  Hint:SetTextColor(.7, .7, .7)
  Hint:SetText("Items whose name contains any of these words are never dropped, whatever their quality. Separate words with commas, for example: knife, fishing pole, bag. Test lists what matches in your bags now.")
  Y = Y - 40

  AddHeader("Bar and tooltip text", Y)
  Y = Y - 22
  AddChoice("Label", "Label", {
    { Value = "full", Text = "JunkDrop" },
    { Value = "short", Text = "JD" },
    { Value = "none", Text = "None" },
  }, Y)
  Y = Y - 30
  AddToggle("Dots", "Show a colored dot for each quality that can be dropped", Y)
  Y = Y - 30
  AddChoice("Show", "Show", {
    { Value = "both", Text = "Name and value" },
    { Value = "value", Text = "Value only" },
    { Value = "name", Text = "Name only" },
  }, Y)
  Y = Y - 30
  AddToggle("ShowCount", "Show the stack size, such as x3", Y)
  Y = Y - 30
  AddChoice("Coins", "Coins", {
    { Value = "icons", Text = "Icons" },
    { Value = "letters", Text = "Letters (g s c)" },
  }, Y)
  Y = Y - 30
  AddChoice("TooltipRows", "Tooltip rows", {
    { Value = 3, Text = "3" },
    { Value = 5, Text = "5" },
    { Value = 10, Text = "10" },
  }, Y)
  Y = Y - 36

  AddHeader("Behavior", Y)
  Y = Y - 22
  AddToggle("ConfirmClick", "Ask before deleting a Poor item when I click the bar item", Y)
  Y = Y - 30
  AddToggle("ConfirmHigher", "Always ask before deleting anything better than Poor", Y)
  Y = Y - 30
  AddToggle("ReportDrops", "Print each deleted item in chat", Y)
  Y = Y - 30

  Frame:SetHeight(-Y + 40) -- Leaves room for the reset button.

  Frame.ResetButton = CreateFrame("Button", nil, Frame, "UIPanelButtonTemplate")
  Frame.ResetButton:SetSize(140, 22)
  Frame.ResetButton:SetPoint("BOTTOMRIGHT", -14, 12)
  Frame.ResetButton:SetText("Reset to defaults")
  Frame.ResetButton:SetScript("OnClick", function()
    JD.Reset()
    SyncAll()
  end)

  ApplySkin()
end

function JD.OpenOptions()
  if not Frame then
    Build()
  end
  if Frame:IsShown() then
    Frame:Hide()
  else
    Frame:Show()
  end
end
