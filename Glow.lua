-- Glow.lua
-- A pulsing red glow around the next stack to be dropped, drawn on the open bags.
-- Only EllesmereUI Bags is supported: it offers a hook for other addons to paint on its item
-- slots. Other bag addons are left alone.

local _, JD = ... -- Addon name and the table shared between this addon's files.

local GlowTexture = "Interface\\Buttons\\UI-ActionButton-Border"
local GlowScale = 2.1 -- Outer glow size relative to the slot; the art has transparent padding.
local BorderWidth = 2 -- Thickness of the solid red border, in pixels.
local Red, Green, Blue = 1, .12, .08

local Glows = setmetatable({}, { __mode = "k" }) -- Slot button -> its glow frame and textures.
local Target -- Bag and slot of the next stack to drop, or false when there is none.
local TargetTime -- When Target was last worked out.
local Painted -- The Target key the bags were last repainted for.

-- Work out which slot is next to drop. The bags paint every slot in one frame, so one scan per
-- frame is shared by all of those paints.
local function GetTarget()
  local Now = GetTime()
  if TargetTime ~= Now then
    TargetTime = Now
    local Stack = JD.Get("Glow") and JD.GetJunkStacks()[1]
    Target = Stack and { Bag = Stack.Bag, Slot = Stack.Slot } or false
  end
  return Target
end

local function GetGlow(Button)
  local Glow = Glows[Button]
  if Glow then
    return Glow
  end
  -- This overlay covers the item icon and is the frame EllesmereUI Bags asks painters to use.
  local Host = Button._textOverlay
  if not Host then
    return nil
  end

  -- Everything lives in one frame so a single animation can pulse all of it.
  local Frame = CreateFrame("Frame", nil, Host)
  Frame:SetAllPoints(Host)
  Frame:SetFrameLevel(Host:GetFrameLevel() + 5)

  -- Two stacked copies of the glow art: it is faint, and additive blending adds them together.
  local Halos = {}
  for Layer = 1, 2 do
    local Halo = Frame:CreateTexture(nil, "OVERLAY", nil, 6 + Layer - 1)
    Halo:SetTexture(GlowTexture)
    Halo:SetBlendMode("ADD")
    Halo:SetVertexColor(Red, Green, Blue)
    Halo:SetPoint("CENTER", Frame, "CENTER")
    Halos[Layer] = Halo
  end

  -- A solid border that stays clearly visible even when the glow is faint.
  local Edges = {}
  for Index, Corners in ipairs({
    { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" },
  }) do
    local Edge = Frame:CreateTexture(nil, "OVERLAY", nil, 7)
    Edge:SetColorTexture(Red, Green, Blue, 1)
    Edge:SetPoint(Corners[1], Frame, Corners[1])
    Edge:SetPoint(Corners[2], Frame, Corners[2])
    if Index <= 2 then
      Edge:SetHeight(BorderWidth)
    else
      Edge:SetWidth(BorderWidth)
    end
    Edges[Index] = Edge
  end

  local Pulse = Frame:CreateAnimationGroup()
  Pulse:SetLooping("BOUNCE")
  local Fade = Pulse:CreateAnimation("Alpha")
  Fade:SetFromAlpha(1)
  Fade:SetToAlpha(.5)
  Fade:SetDuration(.6)

  Glow = { Host = Host, Frame = Frame, Halos = Halos, Edges = Edges, Pulse = Pulse }
  Glows[Button] = Glow
  return Glow
end

local function HideGlow(Button)
  local Glow = Glows[Button]
  if Glow then
    Glow.Pulse:Stop()
    Glow.Frame:Hide()
  end
end

-- Called by EllesmereUI Bags for every slot it paints, so it must also clear the glow from a
-- slot that is no longer the target.
local function Paint(Button, Data)
  local Wanted = GetTarget()
  if Wanted and Data and Data.bag == Wanted.Bag and Data.slot == Wanted.Slot then
    local Glow = GetGlow(Button)
    if Glow then
      local Width, Height = Glow.Host:GetWidth(), Glow.Host:GetHeight()
      if Width and Width > 0 and Height and Height > 0 then
        for _, Halo in ipairs(Glow.Halos) do
          Halo:SetSize(Width * GlowScale, Height * GlowScale)
        end
      end
      Glow.Frame:Show()
      if not Glow.Pulse:IsPlaying() then
        Glow.Pulse:Play()
      end
    end
  else
    HideGlow(Button)
  end
end

-- Make the open bags repaint when the glow should move, appear or go away. Called after every
-- bag change and every setting change; it only repaints when the target actually changed.
function JD.RefreshGlow()
  if not (EUI_Bags and EUI_Bags.RefreshInventory) then
    return
  end
  TargetTime = nil -- Work the target out again from the bags as they are now.
  local Wanted = GetTarget()
  local Key = Wanted and (Wanted.Bag .. ":" .. Wanted.Slot) or "none"
  if Key == Painted then
    return
  end
  if InCombatLockdown() then
    return -- The bags repaint themselves after combat; Painted stays stale so this retries.
  end
  Painted = Key
  if EUI_Bags:IsShown() then
    EUI_Bags:RefreshInventory()
  end
end

-- EllesmereUI Bags is a separate addon, so wait until every addon has loaded.
local Events = CreateFrame("Frame")
Events:RegisterEvent("PLAYER_LOGIN")
Events:SetScript("OnEvent", function()
  if EUI_Bags and EUI_Bags.RegisterItemOverlayIcon then
    EUI_Bags.RegisterItemOverlayIcon("JunkDrop", Paint)
    JD.RefreshGlow()
  end
end)
