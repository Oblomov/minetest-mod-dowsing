-- Dowsing mod. Code licensed under CC0, media licensed under CC BY-SA 3.0 Unported.

-- Dowsing is achieved by hooking into the global time-stepping function and informing the user
-- about nearby “interesting” nodes if they have the rod equipped

-- support for MT game translation.
local S = default.get_translator

-- cache method
local sprintf = string.format

-- Rod checks passively every interval seconds, but detection can be forced by “using” it
local interval = 1
local timer = 0
local default_range = 8

-- Map for player name => HUD index, to update sensing information and to remove the HUD when not wielding the rod
local dowsing_hud = {}

-- Constant strings
local dowsing_nothing = S("You sense nothing in the area")

-- Angle checks
local angle_check = math.pi/4
local angle_loop = math.pi*2

-- Actual dowsing function for given player wielding given rod
local function dowse(player, rod, rod_dowsing)
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

	player_pos.y = player_pos.y + 1
	player_pos = vector.round(player_pos)


	local found = false
	for _, spec in pairs(dowsing) do
		local range = spec.range or default_range
		local nodenames = spec.target
		local node_pos = minetest.find_node_near(player_pos, range, nodenames)
		if node_pos then
			local node = minetest.get_node(node_pos)
			local dist = vector.distance(player_pos, node_pos)

			-- minetest.log("action", string.format("%s senses %s at distance %.1f", player_name, node.name, dist)

			local genloc
			genloc = dist < range/2 and S("nearby") or S("in the area")
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
				minetest.log("action", sprintf("%s hangle %g hangle - math.pi %g", hpos, hangle, hangle - math.pi))

				--genloc = sprintf("%g (%g %g)",player_yaw*180/math.pi, vdir*180/math.pi, hdir*180/math.pi)
				--genloc = sprintf("%s%s (%g | %g => %g)", vpos, hpos, vangle, player_yaw, hangle)
				genloc = sprintf("%s %s%s", genloc, vpos, hpos)
			end
			local msg = S("You sense @1 @2", spec.target_name, genloc)
			hud_text = sprintf("%s\n%s", hud_text, msg)
			found = true
		end
	end
	-- if the action was requested and nothing was found, let the user known
	if not found then
		-- log only if the action was requested
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
	-- increment timer, return if interval hasn't elapsed
	timer = timer + dtime
	if timer < interval then
		return
	end
	timer = timer - interval

	for _, player in pairs(minetest.get_connected_players()) do
		local rod = player:get_wielded_item()
		local rod_dowsing = rod:get_definition().dowsing
		if rod_dowsing ~= nil then
			dowse(player, rod, rod_dowsing)
		else
			-- remove the dowsing hud
			local player_name = player:get_player_name()
			local hud = dowsing_hud[player_name]
			if hud then
				player:hud_remove(hud)
				dowsing_hud[player_name] = nil
			end
		end
	end
end)

-- Rod items

-- Classic dowsing rod, for water, also tells you the general direction
minetest.register_craftitem("dowsing:rod", {
	description = S("Dowsing rod"),
	inventory_image = "dowsing_rod.png",
	wield_image = "dowsing_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("water"), target = "group:water", dir = true, },
	},
	on_use = function(item, user, pointed_thing) return dowse(user, item) end,
})

-- the abstract rod is a “generic” detector that informs the user about nearby blocks of interest,
-- but has no specificity nor direction
minetest.register_craftitem("dowsing:abstract_rod", {
	description = S("Abstract dowsing rod"),
	inventory_image = "dowsing_abstract_rod.png",
	wield_image = "dowsing_abstract_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		-- detect water (TODO other “wet” things)
		{ target_name = S("something wet"), target = "group:water", },
		-- detect lava / fire etc
		{ target_name = S("something hot"), target = "group:igniter", },
		-- detect “interesting” but not necessairly useful things (clay, mossy cobble for dungeons, etc)
		{ target_name = S("something interesting"), target = { "default:clay", "default:mossycobble" }, },
		-- detect useful but common things
		{ target_name = S("something useful"), target = { "default:stone_with_coal", "default:coalblock", "default:gravel" }, },
		-- detect “quite useful” things (ores)
		{
			target_name = S("something quite useful"),
			target = {
				"default:stone_with_copper", "default:stone_with_tin", "default:stone_with_iron",
				"default:copperblock", "default:tinblock", "default:steelblock",
				"default:bronzeblock",
			},
		},
		-- detect “precious” ores
		{
			target_name = S("something precious"),
			target = {
				"default:stone_with_mese", "default:stone_with_gold", "default:stone_with_diamond",
				"default:mese", "default:goldblock", "default:diamondblock",
			},
		},
	},
	on_use = function(item, user, pointed_thing) return dowse(user, item) end,
})

-- element-specific dowsing rods: aside from water, they also identify specific ores
minetest.register_craftitem("dowsing:copper_rod", {
	description = S("Copper dowsing rod"),
	inventory_image = "dowsing_copper_rod.png",
	wield_image = "dowsing_copper_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("water"), target = "group:water", dir = true, },
		{ target_name = S("coal"), target = { "default:stone_with_coal", "default:coalblock", }, },
		{ target_name = S("copper"), target = { "default:stone_with_copper", "default:copperblock", }, dir = true, },
	},
	on_use = function(item, user, pointed_thing) return dowse(user, item) end,
})

minetest.register_craftitem("dowsing:tin_rod", {
	description = S("Tin dowsing rod"),
	inventory_image = "dowsing_tin_rod.png",
	wield_image = "dowsing_tin_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("water"), target = "group:water", dir = true, },
		{ target_name = S("coal"), target = { "default:stone_with_coal", "default:coalblock", }, },
		{ target_name = S("tin"), target = { "default:stone_with_tin", "default:tinblock", }, dir = true, },
	},
	on_use = function(item, user, pointed_thing) return dowse(user, item) end,
})

minetest.register_craftitem("dowsing:steel_rod", {
	description = S("Steel dowsing rod"),
	inventory_image = "dowsing_steel_rod.png",
	wield_image = "dowsing_steel_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("water"), target = "group:water", dir = true, },
		{ target_name = S("coal"), target = { "default:stone_with_coal", "default:coalblock", }, },
		{ target_name = S("iron"), target = { "default:stone_with_iron", "default:steelblock", }, dir = true, },
	},
	on_use = function(item, user, pointed_thing) return dowse(user, item) end,
})

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

minetest.register_craft({
	output = "dowsing:abstract_rod",
	recipe = {
		{ "default:gravel"},
		{ "dowsing:rod"},
	},
})

minetest.register_craft({
	output = "dowsing:copper_rod",
	recipe = {
		{ "default:copper_ingot"},
		{ "dowsing:rod"},
	},
})

minetest.register_craft({
	output = "dowsing:tin_rod",
	recipe = {
		{ "default:tin_ingot"},
		{ "dowsing:rod"},
	},
})

minetest.register_craft({
	output = "dowsing:steel_rod",
	recipe = {
		{ "default:steel_ingot"},
		{ "dowsing:rod"},
	},
})

-- expensive!
minetest.register_craft({
	output = "dowsing:mese_rod",
	recipe = {
		{ "default:mese"},
		{ "dowsing:rod"},
	},
})


-- Fuel recipes

minetest.register_craft({
	type = "fuel",
	recipe = "dowsing:rod",
	burntime = 4, -- 4 times the burntime of group:stick
})

