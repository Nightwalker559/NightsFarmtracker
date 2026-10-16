------------------------------------------------------------------------
-- Night's Farmtracker - Chat filter
-- Hides recurring profession-proc chat lines that flood the chat while
-- farming (e.g. "Your Finesse helps you gather something extra"). Uses
-- Blizzard's own chat pipeline (ChatFrameUtil.AddMessageEventFilter, see
-- Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua): a filter returning
-- true drops the line for the chat frames only - the CHAT_MSG_* events
-- themselves still fire, so loot tracking is not affected.
--
-- The client text of these lines is not part of the UI source, so the
-- phrases to hide are a plain-text list (account-wide, editable with
-- /nft chatfilter add/remove). A line is hidden when it contains any
-- phrase (case-insensitive, no patterns).
------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue or function() return false end

-- Channels the proc lines may arrive on. The filter is cheap (one string
-- search per line, only when the feature is on and the list is not empty).
local EVENTS = {
    "CHAT_MSG_SYSTEM", "CHAT_MSG_SKILL", "CHAT_MSG_TRADESKILLS",
    "CHAT_MSG_OPENING", "CHAT_MSG_LOOT", "CHAT_MSG_COMBAT_MISC_INFO",
}

-- Seeded once into the account DB; afterwards the user's list is the truth.
local DEFAULT_PHRASES = {
    "Eure Finesse hilft Euch",
}

local function GetPhrases()
    local acc = NightsFarmtrackerAccountDB
    if not acc then return nil end
    if acc.chatFilterPhrases == nil then
        acc.chatFilterPhrases = {}
        for i, p in ipairs(DEFAULT_PHRASES) do acc.chatFilterPhrases[i] = p end
    end
    return acc.chatFilterPhrases
end

local function ShouldHide(msg)
    local db = NightsFarmtrackerDB
    if not db or db.chatFilterEnabled == false then return false end
    if type(msg) ~= "string" or issecretvalue(msg) then return false end
    local phrases = GetPhrases()
    if not phrases then return false end
    local lower = msg:lower()
    for _, p in ipairs(phrases) do
        if lower:find(p:lower(), 1, true) then return true end
    end
    return false
end

local function Filter(_, event, msg)
    local hide = ShouldHide(msg)
    -- Debug aid: with /nft debug on, every line mentioning "Finesse" is
    -- logged with its channel, whether or not it is hidden (shows which
    -- event carries the line when the phrase list does not match yet).
    if ns.debugMode and type(msg) == "string" and not issecretvalue(msg)
       and (hide or msg:lower():find("finesse", 1, true)) then
        ns.Log("chatfilter: " .. (hide and "hid " or "saw ") .. tostring(event) .. ": " .. msg)
    end
    return hide
end

-- The exact channel of the proc line is not documented, so besides the
-- list above every other game-generated channel from ChatTypeInfo is
-- covered too. Player chat is left alone (people must never be censored).
local PLAYER_CHAT = {
    SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true, WHISPER = true,
    WHISPER_INFORM = true, PARTY = true, PARTY_LEADER = true, RAID = true,
    RAID_LEADER = true, RAID_WARNING = true, INSTANCE_CHAT = true,
    INSTANCE_CHAT_LEADER = true, GUILD = true, OFFICER = true, CHANNEL = true,
    BN_WHISPER = true, BN_WHISPER_INFORM = true, BN_INLINE_TOAST_BROADCAST = true,
    COMMUNITIES_CHANNEL = true, AFK = true, DND = true, IGNORED = true,
}
local seen = {}
local function Register(addFilter, event)
    if not seen[event] then
        seen[event] = true
        addFilter(event, Filter)
    end
end

local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
    for _, event in ipairs(EVENTS) do Register(addFilter, event) end
    if type(ChatTypeInfo) == "table" then
        for key in pairs(ChatTypeInfo) do
            if type(key) == "string" and not PLAYER_CHAT[key] and not key:find("^CHANNEL") then
                Register(addFilter, "CHAT_MSG_" .. key)
            end
        end
    end
end

------------------------------------------------------------------------
-- /nft chatfilter [on|off|list|add <text>|remove <number>]
------------------------------------------------------------------------
function ns.ChatFilterSlash(rest)
    local L = ns.L
    local arg, text = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    arg = arg:lower()
    local db = NightsFarmtrackerDB
    local phrases = GetPhrases()
    if not db or not phrases then return end

    if arg == "on" or arg == "off" then
        db.chatFilterEnabled = (arg == "on")
        ns.Print(L["chatfilter_state"]:format(db.chatFilterEnabled and L["on"] or L["off"]))
    elseif arg == "add" and text ~= "" then
        phrases[#phrases + 1] = text
        ns.Print(L["chatfilter_added"]:format(text))
    elseif arg == "remove" and tonumber(text) and phrases[tonumber(text)] then
        ns.Print(L["chatfilter_removed"]:format(table.remove(phrases, tonumber(text))))
    elseif arg == "list" or arg == "" then
        ns.Print(L["chatfilter_state"]:format(db.chatFilterEnabled ~= false and L["on"] or L["off"]))
        if #phrases == 0 then
            ns.Print(L["chatfilter_empty"])
        else
            for i, p in ipairs(phrases) do ns.Print(i .. ": " .. p) end
        end
        ns.Print(L["chatfilter_usage"])
    else
        ns.Print(L["chatfilter_usage"])
    end
end
