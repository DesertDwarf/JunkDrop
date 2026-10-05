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
local function ApplySkin()
  if not (Skin and Frame) then
    return
  end
  Skin.Shell(Frame)
  if Frame.Inset then
    Skin.Inset(Frame.Inset)
  end
  if Frame.CloseButton then
    Skin.CloseButton(Frame.CloseButton)
  end
  for _, Button in ipairs(Frame.CheckButtons) do
    Skin.Checkbox(Button)
  end
  Skin.Button(Frame.ResetButton)
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

-- A single on/off setting.
local function AddToggle(Key, Text, Y)
  local Button = NewCheckButton(Text, 16, Y)
  Button:SetScript("OnClick", function(self)
    JD.Set(Key, self:GetChecked() and true or false)
  end)
  tinsert(Syncs, function()
    Button:SetChecked(JD.Get(Key))
  end)
end

-- A pick-one setting drawn as a row of check boxes, so it needs no dropdown template.
local function AddChoice(Key, Title, Choices, Y)
  local TitleText = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  TitleText:SetPoint("TOPLEFT", 16, Y - 5)
  TitleText:SetText(Title)
  for Index, Choice in ipairs(Choices) do
    local Button = NewCheckButton(Choice.Text, 110 + (Index - 1) * 130, Y)
    Button:SetScript("OnClick", function()
      JD.Set(Key, Choice.Value)
      SyncAll() -- Re-check the row so a click on the chosen option cannot un-check it.
    end)
    tinsert(Syncs, function()
      Button:SetChecked(JD.Get(Key) == Choice.Value)
    end)
  end
end

local function Build()
  Frame = CreateFrame("Frame", "JunkDropOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
  Frame:SetSize(520, 340)
  Frame:SetPoint("CENTER")
  Frame:SetFrameStrata("DIALOG")
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

  AddHeader("Bar and tooltip text", -36)
  AddChoice("Label", "Label", {
    { Value = "full", Text = "JunkDrop" },
    { Value = "short", Text = "JD" },
    { Value = "none", Text = "None" },
  }, -58)
  AddChoice("Show", "Show", {
    { Value = "both", Text = "Name and value" },
    { Value = "value", Text = "Value only" },
    { Value = "name", Text = "Name only" },
  }, -88)
  AddToggle("ShowCount", "Show the stack size, such as x3", -118)
  AddChoice("Coins", "Coins", {
    { Value = "icons", Text = "Icons" },
    { Value = "letters", Text = "Letters (g s c)" },
  }, -148)
  AddChoice("TooltipRows", "Tooltip rows", {
    { Value = 3, Text = "3" },
    { Value = 5, Text = "5" },
    { Value = 10, Text = "10" },
  }, -178)

  AddHeader("Behavior", -214)
  AddToggle("ConfirmClick", "Ask before deleting when I click the bar item", -236)
  AddToggle("ReportDrops", "Print each deleted item in chat", -266)

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
