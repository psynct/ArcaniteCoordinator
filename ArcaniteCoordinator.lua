AC = LibStub("AceAddon-3.0"):NewAddon("ArcaniteCoordinator", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceTimer-3.0")
AC.Dialog = LibStub("AceConfigDialog-3.0")
AC.LibDeflate = LibStub("LibDeflate")

local L = LibStub("AceLocale-3.0"):GetLocale("ArcaniteCoordinator")

AC:RegisterChatCommand(L["arc"], "ChatCommand")
AC.VERSION = 108
AC.COMMS_VER = 4
AC.ICON = "Interface/Icons/inv_misc_stonetablet_05"

function GetVersionString(ver)
	if ver >= 10 then
		return GetVersionString(floor(ver/10)) .. "." .. tostring(ver % 10)
	else
		return "v" .. tostring(ver)
	end
end

AC.options = {
	name = format("|T%s:24:24:0:5|t ", AC.ICON) .. L["Arcanite Coordinator"] .. " " .. GetVersionString(AC.VERSION),
	handler = AC,
	type = 'group',
	args = {
		desc = {
			type = "description",
			name = "|CffDEDE42" .. format(L["optionsDesc"], L["arc"], L["config"]),
			fontSize = "medium",
			order = 1,
		},
		minimap = {
			type = "toggle",
			name = L["Minimap Button"],
			desc = L["minimapDesc"],
			order = 3,
			get = function()
				return not AC.db.profile.minimap.hide
			end,
			set = function (info, value)
				AC.db.profile.minimap.hide = not value
				if AC.db.profile.minimap.hide then
					AC.icon:Hide("ArcaniteCoordinator")
				else
					AC.icon:Show("ArcaniteCoordinator")
				end
			end,
		},
	},
}

AC.optionDefaults = {
	profile = {
		minimap = {
			hide = false,
		},
	},
	factionrealm = {
		knownCooldowns = {},
	},
}

function splitString(inputstr, sep)
	local t={}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		table.insert(t, str)
	end
	return t
end

AC.QuestionCooldowns = "AC_qc"
AC.SendKnownCooldown = "AC_skc"
AC.SendAllCooldowns = "AC_sac"

AC.CHAT_PREFIX = format("|cFFFF69B4[%s]|r ", L["ArcaniteCoordinator"])
AC.foundOldVersion = false
AC.ARCANITE_SPELL_ID = 17187
AC.ALCHEMY_300_SPELL_ID = 11611
AC.FORGET_COOLDOWN_SECS = 7 * 24 * 60 * 60
AC.DEBUG = false

local sendAllCooldownsTimer
local requestCooldownsTimer

function AC:OnInitialize()
	AC.ArcaniteCoordinatorLauncher = LibStub("LibDataBroker-1.1"):NewDataObject("ArcaniteCoordinator", {
		type = "launcher",
		text = L["Arcanite Coordinator"],
		icon = AC.ICON,
		OnClick = function(self, button)
			if button == "LeftButton" then
				AC:PrintCooldowns()
			elseif button == "RightButton" then
				AC:ToggleConfigWindow()
			end
		end,
		OnEnter = function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddDoubleLine(format("|cFFFFFFFF%s|r", L["Arcanite Coordinator"]), format("|cFF777777%s|r", GetVersionString(AC.VERSION)))
			GameTooltip:AddLine(L["minimapLeftClickAction"])
			GameTooltip:AddLine(L["minimapRightClickAction"])
			GameTooltip:Show()
		end,
		OnLeave = function(self)
			GameTooltip:Hide()
		end
	})

	AC.db = LibStub("AceDB-3.0"):New("ArcaniteCoordinatorDB", AC.optionDefaults, "Default")
	LibStub("AceConfig-3.0"):RegisterOptionsTable("ArcaniteCoordinator", AC.options)
	AC.ArcaniteCoordinatorOptions = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ArcaniteCoordinator", L["Arcanite Coordinator"])

	AC.icon = LibStub("LibDBIcon-1.0")
	AC.icon:Register("ArcaniteCoordinator", AC.ArcaniteCoordinatorLauncher, AC.db.profile.minimap)

	AC:RegisterEvent("PLAYER_LOGIN")
	AC:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	AC:RegisterComm(AC.QuestionCooldowns, "OnQuestionCooldowns")
	AC:RegisterComm(AC.SendKnownCooldown, "OnSendKnownCooldown")
	AC:RegisterComm(AC.SendAllCooldowns, "OnSendAllCooldowns")
end

function AC:PLAYER_LOGIN()
	AC:UpdateAndSendMyCooldown()
	AC:CleanupCooldowns()
	if requestCooldownsTimer then AC:CancelTimer(requestCooldownsTimer, true); requestCooldownsTimer = nil; end
	requestCooldownsTimer = AC:ScheduleTimer(function()
		AC:RequestCooldowns()
	end, 5)
end

function AC:UNIT_SPELLCAST_SUCCEEDED(_, _, _, spellId)
	if spellId == AC.ARCANITE_SPELL_ID then
		AC:UpdateAndSendMyCooldown()
	end
end

function AC:UpdateMyCooldown()
	local myName = UnitName("player")
	local hasAlchemy275 = false
	if IsSpellKnown(AC.ALCHEMY_300_SPELL_ID) then
		local alchemySpellName = GetSpellInfo(AC.ALCHEMY_300_SPELL_ID)
		for i = 1, GetNumSkillLines() do
			local skillName, _, _, skillRank = GetSkillLineInfo(i)
			skillRank = tonumber(skillRank)
			if alchemySpellName == skillName and skillRank ~= nil then
				hasAlchemy275 = (skillRank >= 275)
				break
			end
		end
	end
	if hasAlchemy275 then
		local start, duration = GetSpellCooldown(AC.ARCANITE_SPELL_ID)
		if start > (2^31 + 2^30) / 1000 then
			-- WORKAROUND wow wraps around negative values that are too big
			start = start - 2^32 / 1000
		end
		local finish
		if start == 0 then
			finish = 0
		else
			local durationRemaining = start + duration - GetTime()
			finish = floor(GetServerTime() + durationRemaining)
		end
		if not AC.db.factionrealm.knownCooldowns[myName] or abs(finish - AC.db.factionrealm.knownCooldowns[myName]["finish"]) > 60 then
			AC.db.factionrealm.knownCooldowns[myName] = {
				["finish"] = finish,
				["lastUpdate"] = GetServerTime(),
			}
			return true
		end
	else
		AC.db.factionrealm.knownCooldowns[myName] = nil
	end
	return false
end

function AC:UpdateAndSendMyCooldown()
	if AC:UpdateMyCooldown() then
		local myName = UnitName("player")
		local cooldownData = AC.db.factionrealm.knownCooldowns[myName]
		AC:SendMessage(AC.SendKnownCooldown, AC.VERSION .. "#" .. AC.COMMS_VER .. "#" .. myName .. ":" .. cooldownData["finish"] .. ":" .. cooldownData["lastUpdate"], "GUILD")
	end
end

function AC:CleanupCooldowns()
	for player, cooldownData in pairs(AC.db.factionrealm.knownCooldowns) do
		if GetServerTime() - cooldownData["lastUpdate"] > AC.FORGET_COOLDOWN_SECS then
			AC.db.factionrealm.knownCooldowns[player] = nil
		elseif cooldownData["finish"] > 0 and GetServerTime() > cooldownData["finish"] then
			AC.db.factionrealm.knownCooldowns[player]["finish"] = 0
		end
	end
end

function AC:SendMessage(prefix, msg, distribution, target)
	if distribution == "GUILD" and not IsInGuild() then
		return
	end
	if AC.DEBUG then
		print("SEND:" .. prefix .. "  " .. UnitName("player") .. "  " .. msg)
	end
	msg = AC.LibDeflate:EncodeForWoWAddonChannel(AC.LibDeflate:CompressDeflate(msg))
	AC:SendCommMessage(prefix, msg, distribution, target)
end

function AC:RequestCooldowns()
	AC:SendMessage(AC.QuestionCooldowns, AC.VERSION .. "#" .. AC.COMMS_VER, "GUILD")
end

function AC:FormatTime(duration)
	if duration < 60 then
		return format("%ds", duration)
	end
	if duration < 60 * 60 then
		return format("%dm %02ds", duration/60, math.fmod(duration, 60))
	end
	return format("%dh %dm", duration/(60 * 60), math.fmod(duration/60, 60))
end

function AC:PrintCooldowns()
	AC:UpdateMyCooldown()
	AC:CleanupCooldowns()
	local cooldownsAtZero = {}
	local remainingCooldowns = {}
	for player, cooldownData in pairs(AC.db.factionrealm.knownCooldowns) do
		if cooldownData["finish"] == 0 then
			table.insert(cooldownsAtZero, player)
		else
			table.insert(remainingCooldowns, {player, cooldownData["finish"]})
		end
	end
	table.sort(cooldownsAtZero)
	if #cooldownsAtZero > 0 then
		print(AC.CHAT_PREFIX .. format("%s: %s", L["Players with cooldown ready"], table.concat(cooldownsAtZero, ", ")))
	end
	local function compare(a,b)
		return a[2] > b[2]
	end
	table.sort(remainingCooldowns, compare)
	if #remainingCooldowns > 0 then
		local playerStrings = {}
		for _, c in pairs(remainingCooldowns) do
			table.insert(playerStrings, c[1] .. " (" .. AC:FormatTime(c[2] - GetServerTime()) .. ")")
		end
		print(AC.CHAT_PREFIX .. format("%s: %s", L["Players on cooldown"], table.concat(playerStrings, ", ")))
	end
	if #cooldownsAtZero == 0 and #remainingCooldowns == 0 then
		print(AC.CHAT_PREFIX .. L["No known cooldowns"])
	end
end

function AC:IsVersionInvalidForComms(ver, commsVer)
	ver = tonumber(ver)
	commsVer = tonumber(commsVer)
	if not AC.foundOldVersion and ver ~= nil and ver > AC.VERSION then
		print(AC.CHAT_PREFIX .. format(L["oldVersionErr"], GetVersionString(AC.VERSION)))
		AC.foundOldVersion = true
	end
	if commsVer ~= AC.COMMS_VER then
		return true
	end
	return false
end

function AC:OnQuestionCooldowns(prefix, msg, distribution, sender)
	if sender == UnitName("player") then return end
	msg = AC.LibDeflate:DecompressDeflate(AC.LibDeflate:DecodeForWoWAddonChannel(msg))
	local ver, commsVer = strsplit("#", msg)
	if AC:IsVersionInvalidForComms(ver, commsVer) then return end
	if AC.DEBUG then
		print("REC:" .. prefix .. "  " .. sender .. "  " .. msg)
	end
	AC:UpdateMyCooldown()
	AC:CleanupCooldowns()
	local playersWithDurations = {}
	for player, cooldownData in pairs(AC.db.factionrealm.knownCooldowns) do
		table.insert(playersWithDurations, player .. ":" .. cooldownData["finish"] .. ":" .. cooldownData["lastUpdate"])
	end
	if #playersWithDurations > 0 then
		if sendAllCooldownsTimer then AC:CancelTimer(sendAllCooldownsTimer, true); sendAllCooldownsTimer = nil; end
		sendAllCooldownsTimer = AC:ScheduleTimer(function()
			AC:SendMessage(AC.SendAllCooldowns, AC.VERSION .. "#" .. AC.COMMS_VER .. "#" .. table.concat(playersWithDurations, ","), "GUILD")
			sendAllCooldownsTimer = nil
		end, random() * 10)
	end
end

function AC:OnSendKnownCooldown(prefix, msg, distribution, sender)
	if sender == UnitName("player") then return end
	msg = AC.LibDeflate:DecompressDeflate(AC.LibDeflate:DecodeForWoWAddonChannel(msg))
	local ver, commsVer, cooldownData = strsplit("#", msg)
	if AC:IsVersionInvalidForComms(ver, commsVer) then return end
	if AC.DEBUG then
		print("REC:" .. prefix .. "  " .. sender .. "  " .. msg)
	end
	local player, finish, lastUpdate = strsplit(":", cooldownData)
	finish = tonumber(finish)
	lastUpdate = tonumber(lastUpdate)
	AC.db.factionrealm.knownCooldowns[player] = {
		["finish"] = finish,
		["lastUpdate"] = lastUpdate
	}
end

function AC:OnSendAllCooldowns(prefix, msg, distribution, sender)
	if sender == UnitName("player") then return end
	msg = AC.LibDeflate:DecompressDeflate(AC.LibDeflate:DecodeForWoWAddonChannel(msg))
	local ver, commsVer, cooldownDatas = strsplit("#", msg)
	if AC:IsVersionInvalidForComms(ver, commsVer) then return end
	if AC.DEBUG then
		print("REC:" .. prefix .. "  " .. sender .. "  " .. msg)
	end
	if requestCooldownsTimer then AC:CancelTimer(requestCooldownsTimer, true); requestCooldownsTimer = nil; end
	if sendAllCooldownsTimer then AC:CancelTimer(sendAllCooldownsTimer, true); sendAllCooldownsTimer = nil; end
	AC:UpdateMyCooldown()
	AC:CleanupCooldowns()
	local sentPlayers = {}
	local newerDataNum = 0
	for _, cooldownData in pairs(splitString(cooldownDatas, ",")) do
		local player, finish, lastUpdate = strsplit(":", cooldownData)
		finish = tonumber(finish)
		lastUpdate = tonumber(lastUpdate)
		sentPlayers[player] = true
		local storedCooldownData = AC.db.factionrealm.knownCooldowns[player]
		if not storedCooldownData then
			AC.db.factionrealm.knownCooldowns[player] = {
				["finish"] = finish,
				["lastUpdate"] = lastUpdate,
			}
		elseif lastUpdate - storedCooldownData["lastUpdate"] > 60 then
			storedCooldownData["finish"] = finish
			storedCooldownData["lastUpdate"] = lastUpdate
		elseif storedCooldownData["lastUpdate"] - lastUpdate > 60 then
			newerDataNum = newerDataNum + 1
		end
	end
	for player, _ in pairs(AC.db.factionrealm.knownCooldowns) do
		if not sentPlayers[player] then
			newerDataNum = newerDataNum + 1
		end
	end
	if newerDataNum > 0 then
		sendAllCooldownsTimer = AC:ScheduleTimer(function()
			local playersWithDurations = {}
			for player, cooldownData in pairs(AC.db.factionrealm.knownCooldowns) do
				table.insert(playersWithDurations, player .. ":" .. cooldownData["finish"] .. ":" .. cooldownData["lastUpdate"])
			end
			AC:SendMessage(AC.SendAllCooldowns, AC.VERSION .. "#" .. AC.COMMS_VER .. "#" .. table.concat(playersWithDurations, ","), "GUILD")
			sendAllCooldownsTimer = nil
		end, random() * 10)
	end
end

function AC:ChatCommand(input)
	input = strtrim(input)
	if input == L["config"] then
		AC:ToggleConfigWindow()
	elseif input == L["cds"] then
		AC:PrintCooldowns()
	elseif input == L["mmb"] then
		local minimap = not AC:getMinimap()
		AC:setMinimap(nil, minimap)
		if minimap then
			print(AC.CHAT_PREFIX .. L["minimapShown"])
		else
			print(AC.CHAT_PREFIX .. L["minimapHidden"])
		end
	else
		print(format("/%s %s - %s\n/%s %s - %s\n/%s %s - %s",
				L["arc"],L["config"], L["configConsole"],
				L["arc"],L["cds"], L["cooldownsConsole"],
				L["arc"],L["mmb"], L["toggleMinimapConsole"]))
	end
end

function AC:ToggleConfigWindow()
	if AC.Dialog.OpenFrames["ArcaniteCoordinator"] then
		AC.Dialog:Close("ArcaniteCoordinator")
	else
		AC.Dialog:Open("ArcaniteCoordinator")
	end
end
