local L = LibStub("AceLocale-3.0"):NewLocale("ArcaniteCoordinator", "enUS", true, true)
L = L or {}
L["Arcanite Coordinator"] = true
L["ArcaniteCoordinator"] = true
L["optionsDesc"] = "Arcanite Coordinator Config (You can type /%s %s to open this)."
L["Minimap Button"] = true
L["minimapDesc"] = "Enable minimap button. Will require a /reload if hiding the button."

-- Chat Messages
L["oldVersionErr"] = "There is a new version of Arcanite Coordinator (%s), please update from curseforge/twitch!"
L["minimapShown"] = "Minimap button shown."
L["minimapHidden"] = "Minimap button hidden. (you will need to type /reload to show changes)"
L["Players with cooldown ready"] = true
L["Players on cooldown"] = true
L["No known cooldowns"] = true

-- Console
L["arc"] = true
L["config"] = true
L["cds"] = true
L["mmb"] = true
L["configConsole"] = "Open/close configuration window."
L["cooldownsConsole"] = "Print currently known guild Arcanite cooldowns."
L["toggleMinimapConsole"] = "Toggle minimap button."

-- Minimap Icon Text
L["minimapLeftClickAction"] = "Left click to print known cooldowns."
L["minimapRightClickAction"] = "Right click to access Arcanite Coordinator settings."
