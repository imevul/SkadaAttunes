local L = LibStub("AceLocale-3.0"):GetLocale("Skada", false)

--"any" locale shortcut
L["Attunements"] = "Attunements"
L["Display"] = "Display"
L["Refresh frequency"] = "Refresh frequency"
L["Trigger events"] = "Trigger events"
L["Cache attunements"] = "Cache attunements"
L["Use timer"] = "Use timer"
L["Timer frequency"] = "Timer frequency"
L["Use kill events"] = "Use kill events"
L["Use damage events"] = "Use damage events"
L["Show item level"] = "Show item level"
L["Show item id"] = "Show item id"
L["Server attunement variables not loaded"] = "Server attunement variables not loaded"

local Skada = Skada
SkadaAttunes = Skada:NewModule(L["Attunements"], "AceTimer-3.0")

local function chat(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local serverCheck = false
local cache_inProgress = {}
local updateTimer = nil
local updateTimerValue = 0

function SkadaAttunes.addToBlockList(itemId)
	if not Skada.db.profile.modules.attuneblocklist then
		Skada.db.profile.modules.attuneblocklist = {}
	end

	Skada.db.profile.modules.attuneblocklist[itemId] = true
	chat(tostring(itemId) .. " added to blocklist")
end

function SkadaAttunes.removeFromBlockList(itemId)
	if not Skada.db.profile.modules.attuneblocklist then
		Skada.db.profile.modules.attuneblocklist = {}
	end

	Skada.db.profile.modules.attuneblocklist[itemId] = nil
	chat(tostring(itemId) .. " removed from blocklist")
end

function SkadaAttunes.isInBlockList(itemId)
	if not Skada.db.profile.modules.attuneblocklist then
		Skada.db.profile.modules.attuneblocklist = {}
	end

	return Skada.db.profile.modules.attuneblocklist[itemId] or false
end

local function getInProgressAttunes(force)
	if not ItemAttuneHas then
		if not serverCheck then
			chat(L["Server attunement variables not loaded"])
			serverCheck = true
		end
		return {}
	end

	if Skada.db.profile.modules.attunescache and force ~= true and #cache_inProgress > 0 then
		return cache_inProgress
	end

	local inProgress = {}
	for id, progress in pairs(ItemAttuneHas) do
		-- Only attunements with some progress
		if progress > 0 and progress < 100 and not SkadaAttunes.isInBlockList(id) then
			table.insert(inProgress, {id = id, progress = progress})
		end
	end

	cache_inProgress = inProgress
	return inProgress
end

local function tableContainsProperty(tbl, property, value)
	for _, data in pairs(tbl) do
		if data[property] == value then
			return true
		end
	end

	return false
end

local function removePlayerAttune(player, id)
	if not player.numAttunes then
		player.numAttunes = 0
		player.attunes = {}
	else
		if player.attunes[id] then
			player.attunes[id] = nil

			player.numAttunes = player.numAttunes - 1

			player.numAttunes = math.max(0, player.numAttunes)
		end
	end
end

local function addOrUpdatePlayerAttune(player, id, progress)
	if not player.numAttunes then
		player.numAttunes = 0
		player.attunes = {}
	end

	if progress < 100 then
		local name, link, _, itemLevel, _, _, _, _, _, icon = GetItemInfo(id)
		local unknown = false

		if not itemLevel then
			itemLevel = 0
		end

		if not name then
			unknown = true
			name = "Unknown item"
		end

		if not icon then
			icon = GetItemIcon(id)
		end

		if Skada.db.profile.modules.attuneshowitemlevel then
			name = "[" .. itemLevel .. "] " .. name
		end

		if unknown or Skada.db.profile.modules.attuneshowitemid then
			name = name .. ' (' .. id .. ')'
		end

		if not player.attunes[id] then
			player.attunes[id] = {
				id = id,
				name = name,
				icon = icon,
				progress = progress,
				link = link
			}

			player.numAttunes = player.numAttunes + 1
		else
			player.attunes[id].name = name
			player.attunes[id].icon = icon
			player.attunes[id].link = link
			player.attunes[id].progress = progress
		end
	else
		removePlayerAttune(player, id)
	end
end

local function get_player(set, playerId, playerName)
	for _, player in ipairs(set.players) do
		if player.id == playerId then
			return player
		end
	end

	return Skada:get_player(set, playerId, playerName)
end

local function updateAttuneProgress(set, attuneEvent, forceRefresh)
	if not set then
		return
	end

	-- Get the player.
	local player = get_player(set, attuneEvent.playerId, attuneEvent.playerName)
	if player then
		local changed = false
		local inProgress = getInProgressAttunes(forceRefresh)

		for _, attune in ipairs(inProgress) do
			changed = addOrUpdatePlayerAttune(player, attune.id, attune.progress) or changed
		end

		for id, _ in pairs(player.attunes) do
			if not tableContainsProperty(inProgress, "id", id) then
				removePlayerAttune(player, id)
				changed = true
			end
		end

		if changed then
			player.last = time()
			set.numAttunes = player.numAttunes
			Skada:UpdateDisplay(true)
		end
	end
end

local lastTimestamp = 0
local attuneProgressEvent = {}

local function OnAttuneProgress(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	if timestamp then
		if lastTimestamp + 1 > timestamp then
			return
		end
		lastTimestamp = timestamp
	end

	attuneProgressEvent.playerId = UnitGUID("player")
	attuneProgressEvent.playerName = UnitName("player")

	local forceRefresh = false
	if eventtype == 'PLAYER_XP_UPDATE' then
		forceRefresh = true
	end

	if Skada.db.profile.modules.attunesusekillevents then
		if eventtype == 'PARTY_KILL' or eventtype == 'SPELL_INSTAKILL' or eventtype == 'UNIT_DIED' or eventtype == 'UNIT_DESTROYED' then
			return
		end
	end

	if not Skada.db.profile.modules.attunesusedamageevents then
		if eventtype == 'SPELL_DAMAGE' or eventtype == 'SPELL_PERIODIC_DAMAGE' or eventtype == 'SPELL_BUILDING_DAMAGE' or eventtype == 'RANGE_DAMAGE' or eventtype == 'SWING_DAMAGE' then
			return
		end
	end

	updateAttuneProgress(Skada.current, attuneProgressEvent, forceRefresh)
	updateAttuneProgress(Skada.total, attuneProgressEvent, forceRefresh)
end

local function OnTimerTick()
	if not Skada.db.profile.modules.attunesusetimer then
		return
	end

	-- Tick the timer more often, and manually count the ticks
	if updateTimerValue <= 0 then
		updateTimerValue = Skada.db.profile.modules.attunetimerfrequency
	else
		updateTimerValue = updateTimerValue - 1
		return
	end

	-- Force cache update
	getInProgressAttunes(true)
	OnAttuneProgress()
	Skada:UpdateDisplay(true)
end

--#region MOD
local function mod_tooltip(win, id, _, tooltip)
	local player = Skada:find_player(win:get_selected_set(), UnitGUID("player"))
	if player then
		local attune = player.attunes[id]
		if attune then
			local link = attune.link
			if not link then
				link = "item:" .. id
			end

			tooltip:SetHyperlink(link)
		end
	end
end

function SkadaAttunes:Update(win, set)
	-- Only update the total/current segments
	if set ~= Skada.total and set ~= Skada.current then
		return
	end

	win.metadata.maxvalue = 100

	-- Aggregate the data.
	local tmp = {}
	for _, player in ipairs(set.players) do
		if player.numAttunes > 0 then
			for id, attune in pairs(player.attunes) do
				if not tmp[id] then
					-- Extra check to remove old attunes
					if ItemAttuneHas[id] or 0 < 100 then
						tmp[id] = {id = attune.id, progress = attune.progress, name = attune.name, icon = attune.icon, link = attune.link}
					end
				else
					tmp[id].progress = attune.progress
				end
			end
		end
	end

	local nr = 1
	for id, attune in pairs(tmp) do
		local d = win.dataset[nr] or {}
		win.dataset[nr] = d

		d.label = attune.name
		d.value = attune.progress
		d.valuetext = ("%02.1f%%"):format(attune.progress)
		d.id = id
		d.icon = attune.icon

		nr = nr + 1
	end

	-- Clean up old stuff
--[[ 	for i = nr, #win.dataset, 1 do
		win.dataset[i].id = nil
	end ]]
end


function SkadaAttunes:OnEnable()
	SkadaAttunes.metadata	= {tooltip = mod_tooltip, wipestale = 1}

	updateTimer = self:ScheduleRepeatingTimer(OnTimerTick, 1)

	Skada:RegisterForCL(OnAttuneProgress, 'PLAYER_XP_UPDATE', {src_is_interesting = true})

	-- Kill events
	Skada:RegisterForCL(OnAttuneProgress, 'PARTY_KILL', {src_is_interesting = true})
	Skada:RegisterForCL(OnAttuneProgress, 'SPELL_INSTAKILL', {src_is_interesting = true})
	Skada:RegisterForCL(OnAttuneProgress, 'UNIT_DIED', {src_is_interesting = true})
	Skada:RegisterForCL(OnAttuneProgress, 'UNIT_DESTROYED', {src_is_interesting = true})

	-- Damage events
	Skada:RegisterForCL(OnAttuneProgress, 'SPELL_DAMAGE', {src_is_interesting = true})
	Skada:RegisterForCL(OnAttuneProgress, 'SPELL_PERIODIC_DAMAGE', {src_is_interesting = true})
	Skada:RegisterForCL(OnAttuneProgress, 'SPELL_BUILDING_DAMAGE', {src_is_interesting = true})
	Skada:RegisterForCL(OnAttuneProgress, 'RANGE_DAMAGE', {src_is_interesting = true})
	Skada:RegisterForCL(OnAttuneProgress, 'SWING_DAMAGE', {src_is_interesting = true})

	Skada:AddMode(self)
end

function SkadaAttunes:OnDisable()
	if updateTimer then
		Skada:CancelTimer(updateTimer)
		updateTimer = nil
	end

	Skada:RemoveMode(self)
end

-- Called by Skada when a new player is added to a set.
function SkadaAttunes:AddPlayerAttributes(player)
	if not player.numAttunes then
		player.numAttunes = 0
		player.attunes = {}

		local inProgress = getInProgressAttunes()

		for _, attune in ipairs(inProgress) do
			addOrUpdatePlayerAttune(player, attune.id, attune.progress)
		end
	end
end

-- Called by Skada when a new set is created.
function SkadaAttunes:AddSetAttributes(set)
	if not set.numAttunes then
		set.numAttunes = 0

		local inProgress = getInProgressAttunes()
		set.numAttunes = #inProgress
	end
end

function SkadaAttunes:GetSetSummary(set)
	return set.numAttunes
end
--#endregion MOD

--#region OPTIONS
local opts = {
	ccoptions = {
		type = "group",
		name = L["Attunements"],
		args = {
			display = {
				type = "group",
				name = L["Display"],
				inline = true,
				order = 1,
				args = {
					showitemlevel = {
						type = "toggle",
						name = L["Show item level"],
						get = function() return Skada.db.profile.modules.attuneshowitemlevel end,
						set = function() Skada.db.profile.modules.attuneshowitemlevel = not Skada.db.profile.modules.attuneshowitemlevel end,
						order = 1
					},

					showitemid = {
						type = "toggle",
						name = L["Show item id"],
						get = function() return Skada.db.profile.modules.attuneshowitemid end,
						set = function() Skada.db.profile.modules.attuneshowitemid = not Skada.db.profile.modules.attuneshowitemid end,
						order = 2
					},
				},
			},

			refreshfrequency = {
				type = "group",
				name = L["Refresh frequency"],
				inline = true,
				order = 2,
				args = {
					usecache = {
						type = "toggle",
						name = L["Cache attunements"],
						get = function() return Skada.db.profile.modules.attunescache end,
						set = function()
							Skada.db.profile.modules.attunescache = not Skada.db.profile.modules.attunescache
							if Skada.db.profile.modules.attunescache then
								Skada.db.profile.modules.attunesusetimer = true
							end
						end,
						order = 1
					},

					usetimer = {
						type = "toggle",
						name = L["Use timer"],
						get = function() return Skada.db.profile.modules.attunesusetimer end,
						set = function()
							Skada.db.profile.modules.attunesusetimer = not Skada.db.profile.modules.attunesusetimer
							if not Skada.db.profile.modules.attunesusetimer then
								Skada.db.profile.modules.attunescache = false
							end
						end,
						order = 2
					},

					timerfrequency = {
						type = "range",
						name = L["Timer frequency"],
						min = 1,
						max = 15,
						step = 1,
						get = function() return Skada.db.profile.modules.attunetimerfrequency end,
						set = function(_, val)
							Skada.db.profile.modules.attunetimerfrequency = val
						end,
						order = 3
					},
				},
			},

			triggerevents = {
				type = "group",
				name = L["Trigger events"],
				inline = true,
				order = 3,
				args = {
					usekillevents = {
						type = "toggle",
						name = L["Use kill events"],
						get = function() return Skada.db.profile.modules.attunesusekillevents end,
						set = function() Skada.db.profile.modules.attunesusekillevents = not Skada.db.profile.modules.attunesusekillevents end,
						order = 1
					},

					usedamageevents = {
						type = "toggle",
						name = L["Use damage events"],
						get = function() return Skada.db.profile.modules.attunesusedamageevents end,
						set = function() Skada.db.profile.modules.attunesusedamageevents = not Skada.db.profile.modules.attunesusedamageevents end,
						order = 2
					},
				},
			},
		},
	}
}

function SkadaAttunes:OnInitialize()
	-- Add our options.
	table.insert(Skada.options.plugins, opts)

	if Skada.db.profile.modules.attunescache == nil then
		Skada.db.profile.modules.attunescache = true
		Skada.db.profile.modules.attunesusetimer = true
	end

	if Skada.db.profile.modules.attunesusetimer == nil then
		Skada.db.profile.modules.attunesusetimer = true
	end

	if Skada.db.profile.modules.attunetimerfrequency == nil then
		Skada.db.profile.modules.attunetimerfrequency = 5
	end

	if Skada.db.profile.modules.attunesusekillevents == nil then
		Skada.db.profile.modules.attunesusekillevents = true
	end

	if Skada.db.profile.modules.attunesusedamageevents == nil then
		Skada.db.profile.modules.attunesusedamageevents = true
	end

	if Skada.db.profile.modules.attuneshowitemlevel == nil then
		Skada.db.profile.modules.attuneshowitemlevel = true
	end

	if Skada.db.profile.modules.attuneshowitemid == nil then
		Skada.db.profile.modules.attuneshowitemid = false
	end

	if Skada.db.profile.modules.attuneblocklist == nil then
		Skada.db.profile.modules.attuneblocklist = {}
	end
end
--#endregion OPTIONS
