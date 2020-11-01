-- Dowsing mod. Code licensed under CC0, media licensed under CC BY-SA 3.0 Unported.

-- Dowsing is achieved by hooking into the global time-stepping function and informing the user
-- about nearby “interesting” nodes if they have the rod equipped

-- support for MT game translation.
local S = default.get_translator

-- cache method
local sprintf = string.format

-- Rod checks passively every interval seconds, but detection can be forced by “using” it
local timer = 0
local interval = minetest.setting_get("dowsing.interval") or 1
local default_range = minetest.setting_get("dowsing.default_range") or 8
local use_range_multiplier = minetest.setting_get("dowsing.use_range_multiplier") or 2

-- Map for player name => HUD index, to update sensing information and to remove the HUD when not wielding the rod
local dowsing_hud = {}

-- Map for player name => last pos and item used. The use_range_multiplier is preserved until
-- one of these things change
local last_use = {}

local function set_last_use(name, pos, tool)
	last_use[name] = { pos = pos, tool = tool:get_name() }
end

-- returns true if the player name has the same pos and tool as last use
-- FIXME we only check for the tool NAME, since I can't find a way to check if the
-- item is the same, but this is good enough (it just means that if you switch to a different
-- rod of the same time it'll keep the multiplier, which is acceptable)
local function match_last_use(name, pos, tool)
	local last = last_use[name]
	if not last then return false end
	local unchanged = vector.equals(last.pos, pos) and last.tool == tool:get_name()
	-- if something changed, remove the last use before returning false
	if not unchanged then last_use[name] = nil end
	return unchanged
end

-- Constant strings
local dowsing_nothing = S("You sense nothing in the area")

-- Angle checks
local angle_check = math.pi/4
local angle_loop = math.pi*2

-- Actual dowsing function for given player wielding given rod
local function dowse(player, rod, rod_dowsing)
	-- passive is true if the dowsing comes from the timer interval, it's false on use
	-- on_use rod_dowsing is not passed, so we can just check for that being not nil
	local passive = rod_dowsing ~= nil
	local dowsing = rod_dowsing or rod:get_definition().dowsing
	local player_pos = player:get_pos()
	local player_name = player:get_player_name()
	local player_yaw = player:get_look_horizontal()

	local hud_text = ""

	local hud = dowsing_hud[player_name] or player:hud_add({
		hud_elem_type = "text",
		position = { x = 0.5, y = 0.5 },
		offset = { x = 0, y = 0 },
		alignment = { x = 0, y = 0 },
		scale = { x = 100, y = 100 },
		text = hud_text,
		number = 0xffffff,
	})

	-- adjust player position to eye level, roundeded to integer
	player_pos.y = player_pos.y + 1
	player_pos = vector.round(player_pos)

	local detection_range_multiplier = 1
	if not passive then
		detection_range_multiplier = use_range_multiplier
		set_last_use(player_name, player_pos, rod)
	else
		local last = last_use[player_name]
		-- keep the range multiplier if we didn't move and the tool didn't change
		if match_last_use(player_name, player_pos, rod) then
			detection_range_multiplier = use_range_multiplier
		end
	end

	local found = false
	for _, spec in pairs(dowsing) do
		local range = spec.range or default_range
		local nearby_range = spec.nearby_range or math.max(math.ceil(range/2), 3)
		local nodenames = spec.target

		-- on use, the detection range gets multiplied by a constant
		local detection_range = range*detection_range_multiplier

		local node_pos = minetest.find_node_near(player_pos, detection_range, nodenames)
		if node_pos then
			local node = minetest.get_node(node_pos)
			local dist = vector.distance(player_pos, node_pos)

			local genloc
			genloc = dist < nearby_range and S("nearby") or S("in the area")
			-- assemble an approximate description of the direction in which the node can be found
			if spec.dir then
				local node_dir = vector.direction(player_pos, node_pos)
				-- pitch of the node_dir (> 0 if above, < 0 if below)
				local vangle = math.atan2(node_dir.y, math.sqrt(node_dir.x*node_dir.x + node_dir.z*node_dir.z))
				-- difference between the yaw of the player and that of the node_dir:
				-- this needs to be adjustements due to periodicity
				local hangle = player_yaw - math.atan2(-node_dir.x, node_dir.z)
				-- bring in -pi, pi range
				while hangle >= math.pi do
					hangle = hangle - angle_loop
				end
				while hangle < -math.pi do
					hangle = hangle + angle_loop
				end

				local vpos = ""
				if vangle < -angle_check then
					vpos = S("below you and ")
				elseif vangle > angle_check then
					vpos = S("above you and ")
				end

				local hpos
				if math.abs(hangle) < angle_check or math.abs(hangle - angle_loop) < angle_check then
					hpos = S("in front of you")
				elseif math.abs(math.abs(hangle) - math.pi) < angle_check then
					hpos = S("behind you")
				elseif hangle > 0 then
					hpos = S("to your right")
				else
					hpos = S("to your left")
				end

				genloc = sprintf("%s %s%s", genloc, vpos, hpos)
			end
			local msg = S("You sense @1 @2", spec.target_name, genloc)
			hud_text = sprintf("%s\n%s", hud_text, msg)
			found = true
		end
	end

	-- update the HUD even if nothing was found, with a specific text
	if not found then
		-- log to server if nothing was found and the action was requested
		if not rod_dowsing then
			minetest.log("action", player_name .. " senses nothing")
		end
		hud_text = sprintf("%s\n%s", hud_text, dowsing_nothing)
	end
	player:hud_change(hud, "text", hud_text)
	dowsing_hud[player_name] = hud
	return nil
end

minetest.register_globalstep(function(dtime)
	if interval <= 0 then return end

	-- increment timer, return if interval hasn't elapsed
	timer = timer + dtime
	if timer < interval then return end

	-- OK, the interval is passed
	timer = timer - interval

	for _, player in pairs(minetest.get_connected_players()) do
		local rod = player:get_wielded_item()
		local rod_dowsing = rod:get_definition().dowsing
		if rod_dowsing ~= nil then
			dowse(player, rod, rod_dowsing)
		else
			local player_name = player:get_player_name()

			-- reset last use
			last_use[player_name] = nil

			-- remove the dowsing HUD is the player is not wielding a rod anymore
			local hud = dowsing_hud[player_name]
			if hud then
				player:hud_remove(hud)
				dowsing_hud[player_name] = nil
			end
		end
	end
end)

-- Public API to allow registration of other rods

dowsing = {}

-- register a new rod named dowsing:<subname>_rod, with the given description, image and dowsing spec
function dowsing.register_rod(subname, description, image, dowsing_spec)
	local item_name = subname and "dowsing:" .. subname .. "_rod" or "dowsing:rod"
	minetest.register_craftitem(item_name, {
		inventory_image = image,
		wield_image = image,
		groups = { dowsing_rod = 1, flammable = 2},
		stack_max = 1,
		on_use = function(item, user, pointed_thing) return dowse(user, item) end,
		dowsing = dowsing_spec
	})
end

-- Register the main rods

-- Classic dowsing rod, for water, also tells you the general direction
dowsing.register_rod(nil, S("Dowsing rod"), "dowsing_rod.png", {
	{ target_name = S("water"), target = "group:water", dir = true, },
})

-- The Abstract rod is a “generic” detector that informs the user about nearby blocks of interest,
-- but has no specificity nor direction

local abstract_dowsing_spec = {}

dowsing.register_rod("abstract", S("Abstract dowsing rod"),  "dowsing_abstract_rod.png", abstract_dowsing_spec)

-- Allow others to extend the abstract rod by creating new specs and/or adding targets
function dowsing.new_abstract_target(name, description, warn_if_exists)
	if abstract_dowsing_spec[name] then
		if warn_if_exists then
			minetest.log("warning", "abstract dowsing spec " .. name .. " exists already")
		end
	else
		abstract_dowsing_spec[name] = { target_name = description, target = {} }
	end
end

function dowsing.add_abstract_target(name, target_spec)
	if type(target_spec) == "table" then
		for _, v in pairs(target_spec) do
			table.insert(abstract_dowsing_spec[name].target, v)
		end
	else
		table.insert(abstract_dowsing_spec[name].target, target_spec)
	end
end

dowsing.new_abstract_target("wet", S("something wet"))
dowsing.new_abstract_target("hot", S("something hot"))
dowsing.new_abstract_target("interesting", S("something interesting"))
dowsing.new_abstract_target("useful", S("something useful"))
dowsing.new_abstract_target("quite_useful", S("something quite useful"))
dowsing.new_abstract_target("precious", S("something precious"))

-- detect water (TODO other “wet” things)
dowsing.add_abstract_target("wet", "group:water")
-- detect lava / fire etc
dowsing.add_abstract_target("hot", "group:igniter")
-- detect “interesting” but not necessairly useful things (clay, mossy cobble for dungeons, etc)
dowsing.add_abstract_target("interesting", { "default:clay", "default:mossycobble" })
-- detect useful but common things
dowsing.add_abstract_target("useful", { "default:stone_with_coal", "default:coalblock", "default:gravel" })
-- detect “quite useful” things (ores)
dowsing.add_abstract_target("quite_useful", {
	"default:stone_with_copper", "default:stone_with_tin", "default:stone_with_iron",
	"default:copperblock", "default:tinblock", "default:steelblock",
	"default:bronzeblock",
})
dowsing.add_abstract_target("precious", {
	"default:stone_with_mese", "default:stone_with_gold", "default:stone_with_diamond",
	"default:mese", "default:goldblock", "default:diamondblock",
})

-- The Mese rod is essentially an ore detector with high specificity
minetest.register_craftitem("dowsing:mese_rod", {
	description = S("Mese dowsing rod"),
	inventory_image = "dowsing_mese_rod.png",
	wield_image = "dowsing_mese_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("water"), target = "group:water", dir = true, },
		{ target_name = S("lava"), target = "group:lava", dir = true, },
		{ target_name = S("coal"), target = { "default:stone_with_coal", "default:coalblock", }, dir = true, },
		{ target_name = S("mese"), target = { "default:stone_with_mese", "default:mese", }, dir = true, },
		{ target_name = S("gold"), target = { "default:stone_with_gold", "default:goldblock", }, dir = true, },
		{ target_name = S("diamond"), target = { "default:stone_with_diamond", "default:diamondblock", }, dir = true, },
	},
	on_use = function(item, user, pointed_thing) return dowse(user, item) end,
})

-- Crafting recipes

minetest.register_craft({
	output = "dowsing:rod",
	recipe = {
		{ "", "group:stick", "" },
		{ "", "group:stick", "" },
		{ "group:stick", "", "group:stick" }
	},
})

-- two equivalent recipes for the abstract rod
minetest.register_craft({
	output = "dowsing:abstract_rod",
	recipe = {
		{ "default:paper", "group:sand", "default:flint" },
		{ "default:paper", "default:gravel", "default:flint"},
		{ "", "dowsing:rod", ""},
	},
})
minetest.register_craft({
	output = "dowsing:abstract_rod",
	recipe = {
		{ "default:paper", "default:gravel", "default:flint"},
		{ "default:paper", "group:sand", "default:flint" },
		{ "", "dowsing:rod", ""},
	},
})

minetest.register_craft({
	output = "dowsing:mese_rod",
	recipe = {
		{ "default:mese"},
		{ "dowsing:rod"},
	},
})


-- element-specific dowsing rods: aside from water, they also identify specific ores

local function register_ore_rod(ingot, desc,  target, ore)
	local ore = ore or ingot
	local target = target or S(ore)
	dowsing.register_rod(ingot, desc, "dowsing_" .. ingot .. "_rod.png", {
		{ target_name = S("water"), target = "group:water", dir = true, },
		{ target_name = S("coal"), target = { "default:stone_with_coal", "default:coalblock", }, },
		{ target_name = S("copper"), target = { "default:stone_with_" ..ore, "default:" .. ingot .. "block", }, dir = true, },
	})
	minetest.register_craft({
		output = "dowsing:" .. ingot .. "_rod",
		recipe = {
			{ "default:" .. ingot .. "_ingot"},
			{ "dowsing:rod"},
		},
})

end

register_ore_rod("copper", S("Copper dowsing rod"))
register_ore_rod("tin", S("Tin dowsing rod"))
register_ore_rod("steel", S("Steel dowsing rod"), "iron")
register_ore_rod("gold", S("Gold dowsing rod"))


-- Fuel recipes

minetest.register_craft({
	type = "fuel",
	recipe = "group:dowsing_rod",
	burntime = 4, -- 4 times the burntime of group:stick
})
