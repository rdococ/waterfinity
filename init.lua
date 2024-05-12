minetest.register_alias("waterminus:water", "waterfinity:water")
minetest.register_alias("waterminus:spring", "waterfinity:spring")
minetest.register_alias("waterminus:lava", "waterfinity:lava")

for i = 1, 7 do
    minetest.register_alias("waterminus:bucket_water_" .. i, "waterfinity:bucket_water_" .. i)
    minetest.register_alias("waterminus:bucket_lava_" .. i, "waterfinity:bucket_lava_" .. i)
end

waterfinity = {}

local S = minetest.get_translator("waterfinity")
local settings = minetest.settings

local set, get, swap, group = minetest.set_node, minetest.get_node, minetest.swap_node, minetest.get_item_group
local getTimer = minetest.get_node_timer
local defs, itemDefs = minetest.registered_nodes, minetest.registered_items
local add, hash = vector.add, minetest.hash_node_position
local floor, random, min, max = math.floor, math.random, math.min, math.max
local insert = table.insert

local naturalFlows = {
    {x = 0, y = -1, z = 0},
    {x = -1, y = 0, z = 0},
    {x = 0, y = 0, z = -1},
    {x = 1, y = 0, z = 0},
    {x = 0, y = 0, z = 1},
}
local naturalSinks = {
    {x = 0, y = 1, z = 0},
    {x = -1, y = 0, z = 0},
    {x = 0, y = 0, z = -1},
    {x = 1, y = 0, z = 0},
    {x = 0, y = 0, z = 1},
}
local adjacent = {
    {x = 0, y = -1, z = 0},
    {x = -1, y = 0, z = 0},
    {x = 0, y = 0, z = -1},
    {x = 1, y = 0, z = 0},
    {x = 0, y = 0, z = 1},
    {x = 0, y = 1, z = 0},
}
local updateMask = {
    {x = 0, y = 0, z = 0},
    {x = -1, y = 0, z = 0},
    {x = 0, y = 0, z = -1},
    {x = 1, y = 0, z = 0},
    {x = 0, y = 0, z = 1},

    {x = -2, y = 0, z = 0},
    {x = -1, y = 0, z = -1},
    {x = 0, y = 0, z = -2},
    {x = 1, y = 0, z = -1},
    {x = 2, y = 0, z = 0},
    {x = 1, y = 0, z = 1},
    {x = 0, y = 0, z = 2},
    {x = -1, y = 0, z = 1},

    {x = 0, y = 1, z = 0},
    {x = -1, y = 1, z = 0},
    {x = 0, y = 1, z = -1},
    {x = 1, y = 1, z = 0},
    {x = 0, y = 1, z = 1},

    {x = -2, y = 1, z = 0},
    {x = -1, y = 1, z = -1},
    {x = 0, y = 1, z = -2},
    {x = 1, y = 1, z = -1},
    {x = 2, y = 1, z = 0},
    {x = 1, y = 1, z = 1},
    {x = 0, y = 1, z = 2},
    {x = -1, y = 1, z = 1}
}
local zero = updateMask[1]
local cardinals = {
    {x = 1, z = 0},
    {x = 0, z = 1},
    {x = -1, z = 0},
    {x = 0, z = -1},
}
local permutations = {
    {1, 2, 3, 4}, {1, 2, 4, 3}, {1, 3, 2, 4}, {1, 3, 4, 2}, {1, 4, 2, 3}, {1, 4, 3, 2}, {2, 1, 3, 4}, {2, 1, 4, 3}, {2, 3, 1, 4}, {2, 3, 4, 1}, {2, 4, 1, 3}, {2, 4, 3, 1},
    {3, 1, 2, 4}, {3, 1, 4, 2}, {3, 2, 1, 4}, {3, 2, 4, 1}, {3, 4, 1, 2}, {3, 4, 2, 1}, {4, 1, 2, 3}, {4, 1, 3, 2}, {4, 2, 1, 3}, {4, 2, 3, 1}, {4, 3, 1, 2}, {4, 3, 2, 1}}
local drain = {}

local empty, air = {}, {name = "air"}
local nop = function () end

local updateInterval = settings:get("waterfinity_update_interval") or 0.25

local function getLevel(pos)
    local level = minetest.get_node_level(pos)

    if level == 7 and get(pos).param2 == 15 then
	local realLevel = minetest.get_meta(pos):get_int("waterfinity:real_level")
	if realLevel ~= 0 then
	    return realLevel
	end
    end
    return level
end

local function setLevel(pos, level, name, downward)
    local node = get(pos)
    set(pos, {name = name or node.name, param2 = level})
    if downward then
	minetest.get_meta(pos):set_int("waterfinity:real_level", level)
	level = 15
    else
	minetest.get_meta(pos):set_int("waterfinity:real_level", 0)
    end
end

-- Returns if we can spread to a position based only on what's below it.
local function spreadable(pos)
    pos.y = pos.y - 1
    local nodeName = get(pos).name
    local r = (nodeName == flowing and getLevel(pos) == 7) or nodeName == source or not defs[nodeName].floodable
    pos.y = pos.y + 1
    return r
end

local function searchDrain(pos)
    local found = {[hash(pos)] = true}
    local queue = {x = pos.x, y = pos.y, z = pos.z, depth = 0}
    local last = queue

    local node = get(pos)
    local level = getLevel(pos)
    local name = node.name
    local def = defs[name]

    while queue do
        local first = queue

        local fNode = get(first)
        local fLevel = getLevel(first)
        local fName = fNode.name
        local fDef = defs[fName] or empty

        local source, flowing = def._waterfinity_source, def._waterfinity_flowing

        if first.depth == 0 or fDef.floodable then
            first.y = first.y - 1
            local bNode = get(first)
            local bLevel = getLevel(first)
            local bName = bNode.name
            local bDef = defs[bName] or empty
            first.y = first.y + 1

            if bDef.floodable or bName == def._waterfinity_flowing and bLevel < 7 or bName == source then
                return first
            elseif first.depth < def._waterfinity_drain_range then
                for _, vec in ipairs(cardinals) do
                    local new = {x = first.x + vec.x, y = first.y, z = first.z + vec.z, depth = first.depth + 1, dir = first.dir or vec}

                    local pstr = hash(new)
                    if not found[pstr] then
                        found[pstr] = true
                        last.next, last = new, new
                    end
                end
            end
        end
        queue = queue.next
    end
end
local function update(pos)
    for _, vec in ipairs(updateMask) do
        pos.x, pos.y, pos.z = pos.x + vec.x, pos.y + vec.y, pos.z + vec.z

        local node, timer = get(pos), getTimer(pos)
        local def = defs[node.name] or empty
        local timeout = timer:get_timeout()

        if group(node.name, "waterfinity") > 0 and timeout == 0 or timeout - timer:get_elapsed() >= updateInterval - 0.01 then
            timer:start(updateInterval)
        end

        pos.x, pos.y, pos.z = pos.x - vec.x, pos.y - vec.y, pos.z - vec.z
    end
end
waterfinity.update = update

local function check_protection(pos, name, text)
    if minetest.is_protected(pos, name) then
        minetest.log("action", (name ~= "" and name or "A mod")
            .. " tried to " .. text
            .. " at protected position "
            .. minetest.pos_to_string(pos)
            .. " with a bucket")
        minetest.record_protection_violation(pos, name)
        return true
    end
    return false
end

local pointSupport = minetest.features.item_specific_pointabilities
local pointabilities = {nodes = {["group:waterfinity"] = true}}

if bucket then
    local on_use = itemDefs["bucket:bucket_empty"].on_use
    minetest.override_item("bucket:bucket_empty", {
        pointabilities = pointabilities,
        on_use = function(itemstack, user, pointed_thing)
            if pointed_thing.type ~= "node" then
                return on_use(itemstack, user, pointed_thing)
            end

            local pos = pointSupport and pointed_thing.under or pointed_thing.above
            local node = get(pos)
            local name = node.name
            local level = getLevel(pos)
            local def = defs[name]
            local item_count = user:get_wielded_item():get_count()

            if group(name, "waterfinity") < 1 then
                return on_use(itemstack, user, pointed_thing)
            end
            if check_protection(pointed_thing.under,
                    user:get_player_name(),
                    "take ".. name) then
                return
            end

            -- default set to return filled bucket
            local isSource = def._waterfinity_source == name
            local giving_back = isSource and def._waterfinity_bucket .. "_7" or (level == 0 and "bucket:bucket_empty" or def._waterfinity_bucket .. "_" .. level)

            -- check if holding more than 1 empty bucket
            if item_count > 1 then
                -- if space in inventory add filled bucked, otherwise drop as item
                local inv = user:get_inventory()
                if inv:room_for_item("main", {name=giving_back}) then
                    inv:add_item("main", giving_back)
                else
                    local pos = user:get_pos()
                    pos.y = math.floor(pos.y + 0.5)
                    minetest.add_item(pos, giving_back)
                end

                -- set to return empty buckets minus 1
                giving_back = "bucket:bucket_empty "..tostring(item_count-1)
            end
            if not isSource then
                set(pos, air)
                update(pos)
            end

            return ItemStack(giving_back)
        end
    })
end

local jitterEnabled = settings:get_bool("waterfinity_jitter")
function waterfinity.register_liquid(liquidDef)
    local source, flowing = liquidDef.source, liquidDef.flowing
    local sanitizedBucket = liquidDef.bucket and liquidDef.bucket:sub(1, 1) == ":" and liquidDef.bucket:sub(2, -1) or liquidDef.bucket

    if source then
        local def = defs[source]
        local extra = {}

        extra.groups = def.groups or {}
        extra.groups.waterfinity = 1

        extra._waterfinity_type = "source"
        extra._waterfinity_source = source
        extra._waterfinity_flowing = flowing
        extra._waterfinity_drain_range = liquidDef.drain_range or 3
        extra._waterfinity_jitter = liquidDef.jitter ~= false and jitterEnabled

        local construct = def.on_construct or nop
        extra.on_construct = function (pos, ...)
            update(pos)
            return construct(pos, ...)
        end

        if def.on_timer then
            error("Cannot register a waterfinity liquid with node timer!")
        end
        extra.on_timer = function (pos)
            local myNode = get(pos)
            local myDef = defs[myNode.name]
            local flowing = myDef._waterfinity_flowing

            for _, vec in ipairs(naturalFlows) do
                pos.x, pos.y, pos.z = pos.x + vec.x, pos.y + vec.y, pos.z + vec.z
                local name = get(pos).name
                local level = getLevel(pos)
                local def = defs[name] or empty

                if name == flowing and getLevel(pos) < 7 or def.floodable then
                    set(pos, {name = flowing, param2 = 7})
                    update(pos)
                end
                pos.x, pos.y, pos.z = pos.x - vec.x, pos.y - vec.y, pos.z - vec.z
            end
        end

        if liquidDef.bucket then
            extra._waterfinity_bucket = sanitizedBucket
        end

        minetest.override_item(source, extra)
    end

    local def = defs[flowing]
    local extra = {}

    extra.groups = def.groups or {}
    extra.groups.waterfinity = 1

    extra._waterfinity_type = "flowing"
    extra._waterfinity_source = source
    extra._waterfinity_flowing = flowing
    extra._waterfinity_drain_range = liquidDef.drain_range or 3
    extra._waterfinity_jitter = liquidDef.jitter ~= false and jitterEnabled

    local construct = def.on_construct or nop
    extra.on_construct = function (pos, ...)
        update(pos)
        return construct(pos, ...)
    end
    local afterPlace = def.after_place_node or nop
    extra.after_place_node = function (pos, ...)
        setLevel(pos, 7)
        return afterPlace(pos, ...)
    end

    if def.on_timer then
        error("Cannot register a waterfinity liquid with node timer!")
    end
    extra.on_timer = function (pos)
        local myNode = get(pos)
        local myLevel = getLevel(pos)
        local myTimer = getTimer(pos)

        local myDef = defs[myNode.name]
        local flowing, source = myDef._waterfinity_flowing, myDef._waterfinity_source

        pos.y = pos.y - 1

        local belowNode = get(pos)
        local belowName = belowNode.name
        local belowDef = defs[belowName] or empty

        if belowName == "ignore" then
            myTimer:start(5)
            return
        end

        local renewable = belowName == source or belowName ~= flowing and not belowDef.floodable
        if renewable then
            pos.y = pos.y + 1
            local sources = 0
            for _, vec in ipairs(cardinals) do
                pos.x, pos.z = pos.x + vec.x, pos.z + vec.z

                local name = get(pos).name
                if name == source then
                    sources = sources + 1
                    if sources >= 2 then
                        pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
                        set(pos, {name = source})
                        return
                    end
                end

                pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
            end
            pos.y = pos.y - 1
        end

        if belowDef.floodable or belowName == flowing and getLevel(pos) < 7 or belowName == source then
            local belowLvl = (belowDef.floodable or belowName == source) and 0 or getLevel(pos)
            local levelGiven = min(7 - belowLvl, myLevel)
            local level = belowLvl + levelGiven

            if belowName ~= source then
		setLevel(pos, level, flowing, true)
            end

            pos.y = pos.y + 1

            if myLevel - levelGiven <= 0 then
                set(pos, air)
            else
                setLevel(pos, myLevel - levelGiven)
            end
            update(pos)

            return
        end

        pos.y = pos.y + 1
        if myLevel == 1 then
            local dir = (searchDrain(pos) or empty).dir
            if dir then
                set(pos, air)

                pos.x, pos.z = pos.x + dir.x, pos.z + dir.z
                set(pos, {name = flowing, param2 = myLevel})
            end

            return
        end

        local minlvl, maxlvl, sum, spreads = myLevel, myLevel, myLevel, {zero, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil}
        local test = {[hash(pos)] = true}

        local perm = permutations[random(1, 24)]
        for i = 1, 4 do
            local vecA = cardinals[perm[i]]
            pos.x, pos.z = pos.x + vecA.x, pos.z + vecA.z

            local pstr = hash(pos)
            if not test[pstr] then
                test[pstr] = true

                local name = get(pos).name
                local level = getLevel(pos)
                local def = defs[name] or empty

                if name == flowing then
                    sum = sum + level
                    maxlvl = maxlvl > level and maxlvl or level
                    minlvl = minlvl < level and minlvl or level
                    spreads[#spreads + 1] = vecA

                    local perm = permutations[random(1, 24)]
                    for i = 1, 4 do
                        local vecB = cardinals[perm[i]]
                        local fullVec = {x = vecA.x + vecB.x, z = vecA.z + vecB.z}

                        pos.x, pos.z = pos.x + vecB.x, pos.z + vecB.z
                        local pstr = hash(pos)
                        if not test[pstr] then
                            test[pstr] = true

                            local name = get(pos).name
                            local level = getLevel(pos)
                            local def = defs[name] or empty

                            if name == flowing then
                                sum = sum + level
                                maxlvl = maxlvl > level and maxlvl or level
                                minlvl = minlvl < level and minlvl or level
                                spreads[#spreads + 1] = fullVec
                            elseif name == source then
                                sum = sum + 7
                                maxlvl = 7
                            elseif def.floodable and spreadable(pos) then -- don't spread over floodables over 1 away
				minlvl = 0
				spreads[#spreads + 1] = fullVec
                            end

                        end
                        pos.x, pos.z = pos.x - vecB.x, pos.z - vecB.z
                    end
                elseif name == source then
                    sum = sum + 7
                    maxlvl = 7
                elseif def.floodable and (renewable or spreadable(pos))then
		    minlvl = 0
		    spreads[#spreads + 1] = vecA
                end
            end

            pos.x, pos.z = pos.x - vecA.x, pos.z - vecA.z
        end

        if maxlvl - minlvl < 2 then
            if not def._waterfinity_jitter then return end

            local swaps = {}
            local perm = permutations[random(1, 24)]
            for i = 1, 4 do
                local vec = cardinals[perm[i]]
                pos.x, pos.z = pos.x + vec.x, pos.z + vec.z

                local neighNode = get(pos)
                local neighName = neighNode.name
                local neighDef = defs[neighName] or empty
                local neighLvl = getLevel(pos)

                if neighName == myNode.name and myLevel - neighLvl == 1 then
                    set(pos, {name = myNode.name, param2 = myLevel})

                    pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
                    if neighLvl == 0 then
                        set(pos, air)
                        update(pos)
                    else
                        set(pos, neighNode)
                    end
                    return
                end

                pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
            end

            return
        end
        if sum > #spreads * 7 then
            sum = #spreads * 7
        end

        local average, leftover = floor(sum / #spreads), sum % #spreads

        for i, vec in ipairs(spreads) do
            pos.x, pos.z = pos.x + vec.x, pos.z + vec.z
            local level = average + (i <= leftover and 1 or 0)

            if level > 0 then
                set(pos, {name = flowing, param2 = level})
            elseif get(pos).name == flowing then
                set(pos, air)
                update(pos)
            end

            pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
        end
    end

    if liquidDef.bucket then
        extra._waterfinity_bucket = sanitizedBucket
    end

    minetest.override_item(flowing, extra)

    if bucket and liquidDef.bucket then
        for i = 1, 7 do
            minetest.register_craftitem(liquidDef.bucket .. (i == 7 and "" or "_" .. i), {
                description = ("%s (%s/7)"):format(liquidDef.bucket_desc, i),
                inventory_image = liquidDef.bucket_images[i],

                stack_max = 1,
                pointabilities = pointabilities,

                on_use = function(itemstack, user, pointed_thing)
                    if pointed_thing.type ~= "node" then
                        return
                    end

                    local pos = pointSupport and pointed_thing.under or pointed_thing.above
                    local node = get(pos)
                    local name = node.name
                    local level = getLevel(pos)
                    local def = defs[name]
                    local item_count = user:get_wielded_item():get_count()

                    if def._waterfinity_flowing ~= liquidDef.flowing then
                        return
                    end
                    if check_protection(pointed_thing.under,
                            user:get_player_name(),
                            "take ".. name) then
                        return
                    end
                    if def._waterfinity_source == name then
                        return ItemStack(sanitizedBucket .. "_7")
                    end

                    local levelTaken = min(level, 7 - i)
                    if levelTaken == level then
                        set(pos, air)
                    else
                        setLevel(pos, level - levelTaken)
                    end
                    update(pos)

                    return ItemStack(sanitizedBucket .. "_" .. (i + levelTaken))
                end,
                on_place = function(itemstack, user, pointed_thing)
                    -- Must be pointing to node
                    if pointed_thing.type ~= "node" then
                        return
                    end

                    local node = minetest.get_node_or_nil(pointed_thing.under)
                    local ndef = node and minetest.registered_nodes[node.name]

                    -- Call on_rightclick if the pointed node defines it
                    if ndef and ndef.on_rightclick and
                            not (user and user:is_player() and
                            user:get_player_control().sneak) then
                        return ndef.on_rightclick(
                            pointed_thing.under,
                            node, user,
                            itemstack)
                    end

                    local lpos

                    -- Check if pointing to a buildable node
                    if ndef and ndef.buildable_to then
                        -- buildable; replace the node
                        lpos = pointed_thing.under
                    else
                        -- not buildable to; place the liquid above
                        -- check if the node above can be replaced

                        lpos = pointed_thing.above
                        node = minetest.get_node_or_nil(lpos)
                        local above_ndef = node and minetest.registered_nodes[node.name]

                        if not above_ndef or not above_ndef.buildable_to then
                            -- do not remove the bucket with the liquid
                            return itemstack
                        end
                    end

                    if check_protection(lpos, user
                            and user:get_player_name()
                            or "", "place "..liquidDef.flowing) then
                        return
                    end

                    local node = get(lpos)
                    local name = node.name
                    local level = getLevel(lpos)
                    local def = defs[name]
                    local item_count = user:get_wielded_item():get_count()

                    if def._waterfinity_source == name then
                        return ItemStack("bucket:bucket_empty")
                    end

                    local levelGiven = node.name == liquidDef.flowing and min(i, 7 - level) or i
                    local newLevel = node.name == liquidDef.flowing and level + levelGiven or levelGiven
                    local giveBack = i - levelGiven == 0 and "bucket:bucket_empty" or sanitizedBucket .. "_" .. i - levelGiven

                    set(lpos, {name = liquidDef.flowing, param2 = newLevel})
                    update(lpos)
                    return ItemStack(giveBack)
                end
            })
        end
        minetest.register_alias(sanitizedBucket .. "_7", sanitizedBucket)
    end
end

minetest.register_on_dignode(function (pos)
    update(pos)
end)

local getHashPos = minetest.get_position_from_hash
minetest.register_on_mapblocks_changed(function (modified_blocks, modified_block_count)
    for hash, _ in pairs(modified_blocks) do
        update(getHashPos(hash))
    end
end)

local checkFalling = minetest.check_for_falling
minetest.check_for_falling = function (pos, ...)
    update(pos)
    return checkFalling(pos, ...)
end

if settings:get_bool("waterfinity_override_all") then
    local liquids, flowingAlts = {}, {}

    local function overrideLiquid(name)
        assert(defs[name], name)
        local source, flowing = defs[name].liquid_alternative_source, defs[name].liquid_alternative_flowing
        local sourceDef, flowingDef = defs[source], defs[flowing]
        if not sourceDef or not flowingDef then return end

        liquids[#liquids + 1] = source
        flowingAlts[source] = flowing

        sourceDef.liquidtype = nil
        sourceDef.liquid_range = nil
        sourceDef.liquid_move_physics = true
        sourceDef.move_resistance = sourceDef.liquid_viscosity or 1
        minetest.register_node(":" .. source, sourceDef)

        flowingDef.liquidtype = nil
        flowingDef.liquid_range = nil
        flowingDef.liquid_move_physics = true
        flowingDef.move_resistance = flowingDef.liquid_viscosity or 1
        if flowingDef.groups then
            flowingDef.groups.not_in_creative_inventory = (sourceDef.groups or empty).not_in_creative_inventory
        end
        minetest.register_node(":" .. flowing, flowingDef)

        local liquidDef = {
            flowing = flowing
        }

        local bucket = bucket.liquids[source]
        local bucketName = (bucket or empty).itemname
        if bucket and bucketName then
            local bucketDef = itemDefs[bucketName]

            minetest.unregister_item(bucketName)

            liquidDef.bucket = ":" .. bucketName
            liquidDef.bucket_desc = bucketDef.description
            liquidDef.bucket_images = {
                ("%s^waterfinity_bucket_bar_1.png"):format(bucketDef.inventory_image),
                ("%s^waterfinity_bucket_bar_2.png"):format(bucketDef.inventory_image),
                ("%s^waterfinity_bucket_bar_3.png"):format(bucketDef.inventory_image),
                ("%s^waterfinity_bucket_bar_4.png"):format(bucketDef.inventory_image),
                ("%s^waterfinity_bucket_bar_5.png"):format(bucketDef.inventory_image),
                ("%s^waterfinity_bucket_bar_6.png"):format(bucketDef.inventory_image),
                ("%s^waterfinity_bucket_bar_7.png"):format(bucketDef.inventory_image)
            }
        end

        waterfinity.register_liquid(liquidDef)
    end

    for name, def in pairs(minetest.registered_nodes) do
        if def.liquidtype == "source" then
            overrideLiquid(name)
        end
    end

    local registerNode = minetest.register_node
    function minetest.register_node(name, def)
        registerNode(name, def)
        if def.liquidtype == "source" or def.liquidtype == "flowing" then
            overrideLiquid(name)
        end
    end

    minetest.register_lbm {
        label = "Upgrade pre-waterfinity liquids",
        name = "waterfinity:override_all",
        nodenames = liquids,
        run_at_every_load = true,
        action = function (pos, node)
            set(pos, {name = flowingAlts[node.name], param2 = 7})
        end
    }

    if default then
        local getBiomeName, id = minetest.get_biome_name, minetest.get_content_id
        local getName = minetest.get_name_from_content_id

        local airID = id("air")
        local encase = {[id("default:water_source")] = true, [id("default:lava_source")] = true, [id("default:river_water_source")] = true}

        minetest.register_on_generated(function (minp, maxp, seed)
            local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
            local biomeMap = minetest.get_mapgen_object("biomemap")

            local area = VoxelArea:new {MinEdge = emin, MaxEdge = emax}
            local data = vm:get_data()
            local paramData = vm:get_param2_data()

            for x = minp.x, maxp.x do
                for z = minp.z, maxp.z do
                    for y = minp.y, maxp.y do
                        local index = area:index(x, y, z)
                        local liquid = data[index]

                        local flowing = flowingAlts[getName(liquid)]
                        flowing = flowing and id(flowing)
                        if flowing then
                            data[index] = flowing
                            paramData[index] = 7
                        end

                        if encase[liquid] then
                            for _, vec in ipairs(naturalFlows) do
                                local nIndex = area:index(x + vec.x, y + vec.y, z + vec.z)
                                local below = vec.y == 0 and area:index(x + vec.x, y - 1, z + vec.z)

                                local def = defs[getName(data[nIndex])] or empty
                                if (data[nIndex] == airID or def.liquidtype == "flowing") and (vec.y ~= 0 or data[below] ~= liquid and (not flowing or data[below] ~= flowing)) then
                                    local biome = biomeMap and biomeMap[nIndex]
                                    local biomeDef = biome and minetest.registered_biomes[getBiomeName(biome)] or empty
                                    data[nIndex] = id(biomeDef.node_stone or "mapgen_stone")
                                end
                            end
                        end
                    end
                end
            end

            vm:set_data(data)
            vm:set_param2_data(paramData)
            vm:calc_lighting()
            vm:write_to_map()
            vm:update_liquids()
        end)

        if bucket then
            for i = 1, 7 do
                minetest.register_craft {
                    type = "fuel",
                    recipe = "waterfinity:bucket_lava_" .. i,
                    burntime = 9,
                    replacements = {{"waterfinity:bucket_lava_" .. i, i == 1 and "bucket:bucket_empty" or "waterfinity:bucket_lava_" .. i - 1}},
                }
            end
        end
    end
elseif default then
    minetest.register_node("waterfinity:water", {
        description = S("Finite Water"),
        tiles = {"waterfinity_spring.png"},
        special_tiles = {
            {
                name = "waterfinity_spring_animated.png",
                backface_culling = false,
                animation = {
                    type = "vertical_frames",
                    aspect_w = 16,
                    aspect_h = 16,
                    length = 2,
                },
            },
            {
                name = "waterfinity_water_animated.png",
                backface_culling = true,
                animation = {
                    type = "vertical_frames",
                    aspect_w = 16,
                    aspect_h = 16,
                    length = 0.5,
                },
            },
        },

        drawtype = "flowingliquid",
        use_texture_alpha = true,
        paramtype = "light",
        paramtype2 = "flowingliquid",

        walkable = false,
        buildable_to = true,
        pointable = false,

        move_resistance = 1,
        liquid_viscosity = 1,
        liquid_move_physics = true,
        liquid_alternative_source = "waterfinity:spring",
        liquid_alternative_flowing = "waterfinity:water",

        post_effect_color = {r = 30, g = 70, b = 90, a = 103},

        leveled_max = 7,

        on_blast = function (pos, intensity) end,
        sounds = default.node_sound_water_defaults()
    })
    minetest.register_node("waterfinity:spring", {
        description = S("Finite Water Spring"),
        tiles = {{
            name = "waterfinity_spring_animated.png",
            backface_culling = false,
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 4,
            },
        }},

        drawtype = "liquid",
        use_texture_alpha = true,
        paramtype = "light",

        walkable = false,
        buildable_to = true,
        pointable = false,

        move_resistance = 1,
        liquid_viscosity = 1,
        liquid_move_physics = true,
        liquid_alternative_source = "waterfinity:spring",
        liquid_alternative_flowing = "waterfinity:water",

        post_effect_color = {r = 30, g = 70, b = 90, a = 103},

        on_blast = function (pos, intensity) end,
        sounds = default.node_sound_water_defaults()
    })

    minetest.register_node("waterfinity:lava", {
        description = S("Finite Lava"),
        tiles = {"default_lava.png"},
        special_tiles = {
            {
                name = "default_lava_flowing_animated.png",
                backface_culling = false,
                animation = {
                    type = "vertical_frames",
                    aspect_w = 16,
                    aspect_h = 16,
                    length = 4,
                },
            },
            {
                name = "default_lava_flowing_animated.png",
                backface_culling = true,
                animation = {
                    type = "vertical_frames",
                    aspect_w = 16,
                    aspect_h = 16,
                    length = 4,
                },
            },
        },
        groups = {lava = 3, igniter = 1},

        drawtype = "flowingliquid",
        use_texture_alpha = true,
        paramtype = "light",
        paramtype2 = "flowingliquid",
        light_source = default.LIGHT_MAX - 1,

        walkable = false,
        buildable_to = true,
        pointable = false,

        move_resistance = 7,
        liquid_viscosity = 7,
        liquid_move_physics = true,
        liquid_alternative_flowing = "waterfinity:lava",

        post_effect_color = {a = 191, r = 255, g = 64, b = 0},
        damage_per_second = 8,

        on_blast = function (pos, intensity) end
    })

    waterfinity.register_liquid {
        source = "waterfinity:spring",
        flowing = "waterfinity:water",

        bucket = "waterfinity:bucket_water",
        bucket_desc = S("Finite Water Bucket"),

        bucket_images = {
            "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_1.png",
            "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_2.png",
            "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_3.png",
            "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_4.png",
            "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_5.png",
            "waterfinity_bucket_water_part.png^waterfinity_bucket_bar_6.png",
            "waterfinity_bucket_water.png^waterfinity_bucket_bar_7.png",
        }
    }
    waterfinity.register_liquid {
        flowing = "waterfinity:lava",

        drain_range = 0,
        jitter = false,

        bucket = "waterfinity:bucket_lava",
        bucket_desc = S("Finite Lava Bucket"),
        bucket_images = {
            "waterfinity_bucket_lava_part.png^waterfinity_bucket_bar_1.png",
            "waterfinity_bucket_lava_part.png^waterfinity_bucket_bar_2.png",
            "waterfinity_bucket_lava_part.png^waterfinity_bucket_bar_3.png",
            "waterfinity_bucket_lava_part.png^waterfinity_bucket_bar_4.png",
            "waterfinity_bucket_lava_part.png^waterfinity_bucket_bar_5.png",
            "waterfinity_bucket_lava_part.png^waterfinity_bucket_bar_6.png",
            "bucket_lava.png^waterfinity_bucket_bar_7.png",
        }
    }

    if bucket then
        for i = 1, 7 do
            minetest.register_craft {
                type = "fuel",
                recipe = "waterfinity:bucket_lava_" .. i,
                burntime = 9,
                replacements = {{"waterfinity:bucket_lava_" .. i, i == 1 and "bucket:bucket_empty" or "waterfinity:bucket_lava_" .. i - 1}},
            }
        end
    end

    if settings:get_bool("waterfinity_replace_mapgen") ~= false then
        local getBiomeName, id = minetest.get_biome_name, minetest.get_content_id
        local getName = minetest.get_name_from_content_id

        local waterFlowingID, waterID, springID, airID = id("default:water_flowing"), id("waterfinity:water"), id("waterfinity:spring"), id("air")
        local lavaFlowingID, lavaID = id("default:lava_flowing"), id("waterfinity:lava")
        local riverWaterSrcID = id("default:river_water_source")

        local equivalents = {[id("default:water_source")] = waterID, [id("default:lava_source")] = lavaID}
        local encase = {[waterID] = true, [lavaID] = true, [springID] = true}

        minetest.register_alias_force("mapgen_water_source", settings:get_bool("waterfinity_ocean_springs") ~= false and "waterfinity:spring" or "default:water_source")

        minetest.register_on_generated(function (minp, maxp, seed)
            local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
            local biomeMap = minetest.get_mapgen_object("biomemap")
            local emin2d = {x = emin.x, y = emin.z, z = 0}

            local esize = vector.add(vector.subtract(emax, emin), 1)
            local esize2d = {x = esize.x, y = esize.z}

            local area = VoxelArea:new {MinEdge = emin, MaxEdge = emax}
            local data = vm:get_data()
            local paramData = vm:get_param2_data()

            for x = emin.x, emax.x do
                for z = emin.z, emax.z do
                    for y = emin.y, emax.y do
                        local index = area:index(x, y, z)
                        local block = data[index]

                        if equivalents[block] then
                            data[index] = equivalents[block]
                            paramData[index] = 7
                        end
                        if encase[data[index]] and x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z then
                            for _, vec in ipairs(naturalFlows) do
                                local nIndex = area:index(x + vec.x, y + vec.y, z + vec.z)

                                local def = defs[getName(data[nIndex])] or empty
                                if data[nIndex] == airID or def.liquidtype == "flowing" then
                                    local biome = biomeMap and biomeMap[nIndex]
                                    local biomeDef = biome and minetest.registered_biomes[getBiomeName(biome)] or empty
                                    data[nIndex] = id(biomeDef.node_stone or "mapgen_stone")
                                end
                            end
                        end
                    end
                end
            end

            vm:set_data(data)
            vm:set_param2_data(paramData)
            vm:calc_lighting()
            vm:write_to_map()
            vm:update_liquids()
        end)
    end

    function waterfinity.cool_lava(pos, node)
        if getLevel(pos) == 7 then
            minetest.set_node(pos, {name = "default:obsidian"})
        else -- Lava flowing
            minetest.set_node(pos, {name = "default:stone"})
        end
        minetest.sound_play("default_cool_lava", {pos = pos, max_hear_distance = 16, gain = 0.2}, true)
    end

    if minetest.settings:get_bool("enable_lavacooling") ~= false then
        minetest.register_abm {
            label = "Finite lava cooling",
            nodenames = {"waterfinity:lava"},
            neighbors = {"waterfinity:water", "waterfinity:spring"},
            interval = 1,
            chance = 1,
            catch_up = false,
            action = waterfinity.cool_lava,
        }
    end
end

if mesecon then
    local function on_mvps_move(moved_nodes)
        for _, callback in ipairs(mesecon.on_mvps_move) do
            callback(moved_nodes)
        end
    end
    local function are_protected(positions, player_name)
        local mode = mesecon.setting("mvps_protection_mode", "compat")
        if mode == "ignore" then
            return false
        end
        local name = player_name
        if player_name == "" or not player_name then -- legacy MVPS
            if mode == "normal" then
                name = "$unknown" -- sentinel, for checking for *any* protection
            elseif mode == "compat" then
                return false
            elseif mode == "restrict" then
                return true
            else
                error("Invalid protection mode")
            end
        end
        local is_protected = minetest.is_protected
        for _, pos in pairs(positions) do
            if is_protected(pos, name) then
                return true
            end
        end
        return false
    end
    local function add_pos(positions, pos)
        local hash = minetest.hash_node_position(pos)
        positions[hash] = pos
    end

    -- tests if the node can be pushed into, e.g. air, water, grass
    local function node_replaceable(name)
        local nodedef = minetest.registered_nodes[name]

        if group(name, "waterfinity") > 0 then
            return false
        end

        -- everything that can be an mvps stopper (unknown nodes and nodes in the
        -- mvps_stoppers table) must not be replacable
        -- Note: ignore (a stopper) is buildable_to, but we do not want to push into it
        if not nodedef or mesecon.mvps_stoppers[name] then
            return false
        end

        return nodedef.buildable_to or false
    end

    function mesecon.mvps_get_stack(pos, dir, maximum, all_pull_sticky)
        -- determine the number of nodes to be pushed
        local nodes = {}
        local pos_set = {}
        local frontiers = mesecon.fifo_queue.new()
        frontiers:add(vector.new(pos))

        local prevLiquid

        for np in frontiers:iter() do
            local np_hash = minetest.hash_node_position(np)
            local nn = not pos_set[np_hash] and minetest.get_node(np)

            if nn and not node_replaceable(nn.name) then
                local compress = false
                if defs[nn.name]._waterfinity_flowing == nn.name then
                    if prevLiquid and prevLiquid.name == nn.name then
                        if prevLiquid.param2 % 8 + nn.param2 % 8 <= 7 then
                            compress = true
                        end
                    end
                    prevLiquid = nn
                else
                    prevLiquid = nil
                end

                pos_set[np_hash] = true
                table.insert(nodes, {node = nn, pos = np})
                if #nodes > maximum then return nil end

                if not compress then
                    -- add connected nodes to frontiers
                    local nndef = minetest.registered_nodes[nn.name]
                    if nndef and nndef.mvps_sticky then
                        local connected = nndef.mvps_sticky(np, nn)
                        for _, cp in ipairs(connected) do
                            frontiers:add(cp)
                        end
                    end

                    frontiers:add(vector.add(np, dir))

                    -- If adjacent node is sticky block and connects add that
                    -- position
                    for _, r in ipairs(mesecon.rules.alldirs) do
                        local adjpos = vector.add(np, r)
                        local adjnode = minetest.get_node(adjpos)
                        local adjdef = minetest.registered_nodes[adjnode.name]
                        if adjdef and adjdef.mvps_sticky then
                            local sticksto = adjdef.mvps_sticky(adjpos, adjnode)

                            -- connects to this position?
                            for _, link in ipairs(sticksto) do
                                if vector.equals(link, np) then
                                    frontiers:add(adjpos)
                                end
                            end
                        end
                    end

                    if all_pull_sticky then
                        frontiers:add(vector.subtract(np, dir))
                    end
                end
            end
        end

        return nodes
    end

    -- pos: pos of mvps
    -- stackdir: direction of building the stack
    -- movedir: direction of actual movement
    -- maximum: maximum nodes to be pushed
    -- all_pull_sticky: All nodes are sticky in the direction that they are pulled from
    -- player_name: Player responsible for the action.
    --  - empty string means legacy MVPS, actual check depends on configuration
    --  - "$unknown" is a sentinel for forcing the check
    function mesecon.mvps_push_or_pull(pos, stackdir, movedir, maximum, all_pull_sticky, player_name)
        local nodes = mesecon.mvps_get_stack(pos, movedir, maximum, all_pull_sticky)

        if not nodes then return end

        local protection_check_set = {}
        local pushing = vector.equals(stackdir, movedir)
        if pushing then -- pushing
            add_pos(protection_check_set, pos)
        end
        -- determine if one of the nodes blocks the push / pull
        local pushLiquid = false
        for id, n in ipairs(nodes) do
            if mesecon.is_mvps_stopper(n.node, movedir, nodes, id) then
                return
            end
            if defs[n.node.name]._waterfinity_flowing == n.node.name then
                -- Nasty hack
                if pushLiquid then
                    if n.node.name ~= pushLiquid then return end

                    local prev = nodes[id - 1]
                    local prevLevel = prev.node.param2 % 8

                    local totalLevel = prevLevel + n.node.param2 % 8

                    if totalLevel <= 7 then
                        prev.node.param2 = totalLevel
                        for i = id, #nodes do
                            table.remove(nodes, id)
                        end
                        table.insert(nodes, "stop")
                        break
                    end
                end

                pushLiquid = n.node.name
            elseif pushLiquid then
                return
            end

            add_pos(protection_check_set, n.pos)
            add_pos(protection_check_set, vector.add(n.pos, movedir))
        end
        if are_protected(protection_check_set, player_name) then
            return false, "protected"
        end

        -- remove all nodes
        for _, n in ipairs(nodes) do
            if n == "stop" then break end

            n.meta = minetest.get_meta(n.pos):to_table()
            local node_timer = minetest.get_node_timer(n.pos)
            if node_timer:is_started() then
                n.node_timer = {node_timer:get_timeout(), node_timer:get_elapsed()}
            end
            minetest.remove_node(n.pos)
        end

        local oldstack = mesecon.tablecopy(nodes)

        -- update mesecons for removed nodes ( has to be done after all nodes have been removed )
        for _, n in ipairs(nodes) do
            if n == "stop" then break end
            mesecon.on_dignode(n.pos, n.node)
        end

        -- add nodes
        for _, n in ipairs(nodes) do
            if n == "stop" then break end
            local np = vector.add(n.pos, movedir)

            -- Turn off conductors in transit
            local conductor = mesecon.get_conductor(n.node.name)
            if conductor and conductor.state ~= mesecon.state.off then
                n.node.name = conductor.offstate or conductor.states[1]
            end

            minetest.set_node(np, n.node)
            minetest.get_meta(np):from_table(n.meta)
            if n.node_timer then
                minetest.get_node_timer(np):set(unpack(n.node_timer))
            end
        end

        local moved_nodes = {}
        for i in ipairs(nodes) do
            if nodes[i] == "stop" then break end

            moved_nodes[i] = {}
            moved_nodes[i].oldpos = nodes[i].pos
            nodes[i].pos = vector.add(nodes[i].pos, movedir)
            moved_nodes[i].pos = nodes[i].pos
            moved_nodes[i].node = nodes[i].node
            moved_nodes[i].meta = nodes[i].meta
            moved_nodes[i].node_timer = nodes[i].node_timer
        end

        on_mvps_move(moved_nodes)

        return true, nodes, oldstack
    end
end
