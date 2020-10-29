
-- Dowsing is achieved by hooking into the global time-stepping function and informing the user
-- about nearby “interesting” nodes if they have the rod equipped

-- support for MT game translation.
local S = default.get_translator

-- Rod checks only every interval seconds
local interval = 1
local timer = 0
local default_range = 16


-- Actual dowsing function for given player wielding given rod
local function dowse(player, rod, rod_dowsing)
	local dowsing = rod_dowsing or rod:get_definition().dowsing
	local player_pos = player:get_pos()
	local player_name = player:get_player_name()

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

			local msg = string.format("%s senses %s at distance %.1f", player_name, node.name, dist)
			minetest.log("action", msg)

			local genloc = dist < range/2 and S("nearby") or S("in the area")
			msg = S("You sense @1 @2", spec.target_name, genloc)
			minetest.chat_send_player(player_name, msg)
			found = true
		end
	end
	-- if the action was requested and nothing was found, let the user known
	if not rod_dowsing and not found then
		minetest.log("action", player_name .. " senses nothing")
		minetest.chat_send_player(player_name, S("You sense nothing in the area"))
	end
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
		end
	end
end)

-- Rod items

minetest.register_craftitem("dowsing:rod", {
	description = S("Dowsing rod"),
	inventory_image = "dowsing_rod.png",
	wield_image = "dowsing_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("water"), target = "group:water" },
	},
	on_use = function(item, user, pointed_thing) return dowse(user, item) end,
})

minetest.register_craftitem("dowsing:abstract_rod", {
	description = S("Abstract dowsing rod"),
	inventory_image = "abstract_dowsing_rod.png",
	wield_image = "abstract_dowsing_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("something wet"), target = "group:water", },
		{ target_name = S("something hot"), target = "group:igniter", },
		{
			target_name = S("something useful"),
			target = {
				"default:stone_with_coal", "default:stone_with_copper", "default:stone_with_tin", "default:stone_with_iron",
				"default:coalblock", "default:copperblock", "default:tinblock", "default:steelblock",
				"default:bronzeblock",
			},
		},
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

minetest.register_craftitem("dowsing:steel_rod", {
	description = S("Steel dowsing rod"),
	inventory_image = "steel_dowsing_rod.png",
	wield_image = "steel_dowsing_rod.png^[transformFX",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target_name = S("water"), target = "group:water", },
		{ target_name = S("coal"), target = { "default:stone_with_coal", "default:coalblock", }, },
		{ target_name = S("iron"), target = { "default:stone_with_iron", "default:steelblock", }, },
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
	output = "dowsing:steel_rod",
	recipe = {
		{ "default:steel_ingot"},
		{ "dowsing:rod"},
	},
})


-- Fuel recipes

minetest.register_craft({
	type = "fuel",
	recipe = "dowsing:rod",
	burntime = 4, -- 4 times the burntime of group:stick
})


