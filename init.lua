
-- Dowsing is achieved by hooking into the global time-stepping function and informing the user
-- about nearby “interesting” nodes if they have the rod equipped

-- support for MT game translation.
local S = default.get_translator

-- Rod checks only every interval seconds
local interval = 1
local timer = 0


-- Actual dowsing function for given player wielding given rod
local function dowse(player, rod, rod_dowsing)
	local dowsing = rod_dowsing or rod:get_definition().dowsing
	local player_pos = player:get_pos()
	player_pos.y = player_pos.y + 1
	player_pos = vector.round(player_pos)

	local found = false
	for _, spec in pairs(dowsing) do
		local range = spec.range
		local nodenames = spec.target
		local node_pos = minetest.find_node_near(player_pos, range, nodenames)
		if node_pos then
			local node = minetest.get_node(node_pos)
			local dist = vector.distance(player_pos, node_pos)
			local msg = player:get_player_name() .. " senses " .. node.name .. " at distance " .. tostring(dist)
			minetest.chat_send_player(player:get_player_name(), msg)
			minetest.log("action", msg)
			found = true
		end
	end
	if not found then
		minetest.chat_send_player(player:get_player_name(), player:get_player_name() .. " senses nothing")
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
	-- TODO this currently held upside down 8-/
	inventory_image = "dowsing_rod.png",
	groups = { dowsing_rod = 1, flammable = 2},
	stack_max = 1,
	dowsing = {
		{ target = "group:water", range = 10 }
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

-- Fuel recipes

minetest.register_craft({
	type = "fuel",
	recipe = "dowsing:rod",
	burntime = 4, -- 4 times the burntime of group:stick
})


