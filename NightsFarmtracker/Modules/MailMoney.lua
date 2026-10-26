------------------------------------------------------------------------
-- Night's Farmtracker - Mail money message (optional)
-- Hides the client's own chat line for money received while the mailbox is
-- open (taking auction proceeds), for addons that print their own summary.
-- A chat filter only affects what the chat shows: events still reach every
-- addon, so the Direct gold counter is unchanged.
-- Off by default; toggled via Settings -> Display.
------------------------------------------------------------------------
local mailOpen = false

local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
AddFilter("CHAT_MSG_MONEY", function()
    return mailOpen and NightsFarmtrackerDB and NightsFarmtrackerDB.hideMailMoney == true
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")
frame:SetScript("OnEvent", function(_, event) mailOpen = event == "MAIL_SHOW" end)
