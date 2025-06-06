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
local getLevel, setLevel, getTimer = minetest.get_node_level, minetest.set_node_level, minetest.get_node_timer
local getMeta = minetest.get_meta
local defs, itemDefs = minetest.registered_nodes, minetest.registered_items
local add, hash = vector.add, minetest.hash_node_position
local floor, random, min, max, abs = math.floor, math.random, math.min, math.max, math.abs
local insert = table.insert

local jittercheck

local MAX_LVL = 8

local function getLiquidLevel(pos)
    if group(get(pos).name, "waterfinity") < 1 then return 0 end
    return getLevel(pos) + 1
end
local function setLiquidLevel(pos, level)
    if level <= 0 then
        set(pos, {name = "air"})
        return
    end
    if level == 1 then
        set(pos, {name = get(pos).name, param2 = level - 1})
        return
    end
    setLevel(pos, level - 1)
end
local function setLiquid(pos, liquid, level)
    if level <= 0 then
        set(pos, {name = "air"})
        return
    end
    set(pos, {name = liquid, param2 = level - 1})
end

function waterfinity.get_level(pos)
    local name = get(pos).name
    if name == defs[name]._waterfinity_source then
        return MAX_LVL
    end
    return getLiquidLevel(pos)
end
waterfinity.set_level = setLiquidLevel
waterfinity.set = setLiquid

function waterfinity.pull(pos, liquid, level)
    local name = get(pos).name
    
    if not level then
        level = liquid
        liquid = defs[name]._waterfinity_flowing
        
        if not liquid then return 0 end
    end
    
    if name ~= liquid then
        if name == defs[liquid]._waterfinity_source then
            return MAX_LVL, liquid
        end
        return 0, liquid
    end
    
    local current = getLiquidLevel(pos)
    if current == 0 then return 0, liquid end
    
    local taken = min(current, level)
    setLiquidLevel(pos, current - taken)
    
    return taken, liquid
end
function waterfinity.push(pos, liquid, level)
    local name = get(pos).name
    if name ~= liquid then
        if name == defs[liquid]._waterfinity_source then
            return 0
        end
        if not defs[name].floodable then
            return level
        end
    end
    
    local current = getLiquidLevel(pos)
    local added = min(level, MAX_LVL-current)
    setLiquidLevel(pos, current + added)
    
    return level-added
end

--[[local function setMomentum(pos, mx, mz)
    local meta = getMeta(pos)
    if mx then meta:set_float("mx", mx) end
    if mz then meta:set_float("mz", mz) end
end
local function getMomentum(pos)
    local meta = getMeta(pos)
    return meta:get_float("mx") or 0, meta:get_float("mz") or 0
end]]

local naturalFlows = {
    {x = 0, y = -1, z = 0},
    {x = -1, y = 0, z = 0},
    {x = 0, y = 0, z = -1},
    {x = 1, y = 0, z = 0},
    {x = 0, y = 0, z = 1},
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

local empty, air = {}, {name = "air"}
local nop = function () end

local updateInterval = settings:get("waterfinity_update_interval") or 0.25

local function searchDrain(pos)
    local found = {[hash(pos)] = true}
    local queue = {x = pos.x, y = pos.y, z = pos.z, depth = 0}
    local last = queue
    
    local node = get(pos)
    local level = getLiquidLevel(pos)
    local name = node.name
    local def = defs[name]
    
    while queue do
        local first = queue
        
        local fNode = get(first)
        local fLevel = getLiquidLevel(first)
        local fName = fNode.name
        local fDef = defs[fName] or empty
        
        local source, flowing = def._waterfinity_source, def._waterfinity_flowing
        
        if first.depth == 0 or fDef.floodable then
            first.y = first.y - 1
            local bNode = get(first)
            local bLevel = getLiquidLevel(first)
            local bName = bNode.name
            local bDef = defs[bName] or empty
            first.y = first.y + 1
            
            if bDef.floodable or bName == def._waterfinity_flowing and bLevel < MAX_LVL or bName == source then
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
        
        if group(node.name, "waterfinity") > 0 and timeout == 0 then
            local src = def._waterfinity_source == node.name and 1/131072 or 0
            
            local uptime = minetest.get_server_uptime()
            timer:start(updateInterval - (uptime % updateInterval) + pos.y * 1/65536 + src)
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
            local level = getLiquidLevel(pos)
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
            local giving_back = isSource and def._waterfinity_bucket .. "_" .. MAX_LVL or (level == 0 and "bucket:bucket_empty" or def._waterfinity_bucket .. "_" .. level)

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
if jitterEnabled == nil then jitterEnabled = true end
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
        --extra._waterfinity_jitter = liquidDef.jitter ~= false and jitterEnabled
        
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
                local level = getLiquidLevel(pos)
                local def = defs[name] or empty
                
                if name == flowing and getLiquidLevel(pos) < MAX_LVL or def.floodable then
                    setLiquid(pos, flowing, MAX_LVL)
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
    
    extra.groups.waterfinity_jitter = extra._waterfinity_jitter and 1 or nil
    
    local construct = def.on_construct or nop
    extra.on_construct = function (pos, ...)
        if jittercheck(pos) then
            update(pos)
        end
        return construct(pos, ...)
    end
    local afterPlace = def.after_place_node or nop
    extra.after_place_node = function (pos, ...)
        setLiquidLevel(pos, MAX_LVL)
        return afterPlace(pos, ...)
    end
    
    if def.on_timer then
        error("Cannot register a waterfinity liquid with node timer!")
    end
    extra.on_timer = function (pos)
        local myNode = get(pos)
        local myLevel = getLiquidLevel(pos)
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
        
        -- Renewability
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
        
        -- Falling fluid
        if belowDef.floodable or belowName == flowing and getLiquidLevel(pos) < MAX_LVL or belowName == source then
            local belowLvl = (belowDef.floodable or belowName == source) and 0 or getLiquidLevel(pos)
            local levelGiven = min(MAX_LVL - belowLvl, myLevel)
            local level = belowLvl + levelGiven
            
            if belowName ~= source then
                setLiquid(pos, flowing, level)
            end
            
            pos.y = pos.y + 1
            
            if myLevel - levelGiven <= 0 then
                set(pos, air)
            else
                setLiquidLevel(pos, myLevel - levelGiven)
            end
            update(pos)
            
            return
        end
        
        -- Thin liquid draining
        pos.y = pos.y + 1
        if myLevel == 1 then
            local dir = (searchDrain(pos) or empty).dir
            if dir then
                set(pos, air)
                
                pos.x, pos.z = pos.x + dir.x, pos.z + dir.z
                setLiquid(pos, flowing, myLevel)
            end
            
            return
        end
        
        -- Spread, with provisions to restrict spread if a waterfall is detected
        local minlvl, maxlvl, sum, spreads = myLevel, myLevel, myLevel, {zero, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil}
        local test = {[hash(pos)] = true}
        local bflood = false
        
        local perm = permutations[random(1, 24)]
        for _, i in ipairs(perm) do
            local vecA = cardinals[perm[i]]
            pos.x, pos.z = pos.x + vecA.x, pos.z + vecA.z
            
            pos.y = pos.y - 1
            
            local name = get(pos).name
            local level = getLiquidLevel(pos)
            local def = defs[name] or empty
            
            local fail = false
            local maybflood = false
            if name == flowing and level < 8 or def.floodable then
                if not bflood then
                    maybflood = true
                end
            elseif bflood then
                fail = true
            end
            
            pos.y = pos.y + 1

            local pstr = hash(pos)
            if not fail and not test[pstr] then
                test[pstr] = true
                
                local name = get(pos).name
                local level = getLiquidLevel(pos)
                local def = defs[name] or empty
                
                if maybflood and (name == flowing or def.floodable) then
                    bflood = true
                    minlvl, maxlvl, sum, spreads = myLevel, myLevel, myLevel, {zero, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil}
                end
                if name == flowing then
                    sum = sum + level
                    maxlvl = maxlvl > level and maxlvl or level
                    minlvl = minlvl < level and minlvl or level
                    spreads[#spreads + 1] = vecA
                    
                    if not bflood then
                        local perm = permutations[random(1, 24)]
                        for _, i in ipairs(perm) do
                            local vecB = cardinals[perm[i]]
                            local fullVec = {x = vecA.x + vecB.x, z = vecA.z + vecB.z}
                            
                            pos.x, pos.z = pos.x + vecB.x, pos.z + vecB.z
                            local pstr = hash(pos)
                            if not test[pstr] then
                                test[pstr] = true
                                
                                local name = get(pos).name
                                local level = getLiquidLevel(pos)
                                local def = defs[name] or empty
                                
                                if name == flowing then
                                    sum = sum + level
                                    maxlvl = maxlvl > level and maxlvl or level
                                    minlvl = minlvl < level and minlvl or level
                                    spreads[#spreads + 1] = fullVec
                                elseif name == source then
                                    sum = sum + MAX_LVL
                                    maxlvl = MAX_LVL
                                elseif def.floodable then
                                    minlvl = 0
                                    spreads[#spreads + 1] = fullVec
                                end
                                
                            end
                            pos.x, pos.z = pos.x - vecB.x, pos.z - vecB.z
                        end
                    end
                elseif name == source then
                    sum = sum + MAX_LVL
                    maxlvl = MAX_LVL
                elseif def.floodable then
                    minlvl = 0
                    spreads[#spreads + 1] = vecA
                end
            end
            
            pos.x, pos.z = pos.x - vecA.x, pos.z - vecA.z
        end
        
        if maxlvl == minlvl then return end
        
        -- Small-scale jitter step. Not sure if necessary anymore
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
                local neighLvl = getLiquidLevel(pos)
                
                if neighName == myNode.name and myLevel - neighLvl == 1 then
                    setLiquid(pos, myNode.name, myLevel)
                    
                    pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
                    if neighLvl == 0 then
                        set(pos, air)
                        --update(pos)
                    else
                        set(pos, neighNode)
                    end
                    return
                end
                
                pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
            end
            
            return
        end
        
        -- Finally, apply the results from our spreading logic
        if sum > #spreads * MAX_LVL then
            sum = #spreads * MAX_LVL
        end
        
        if bflood and sum <= (#spreads-1) * MAX_LVL then
            -- spreads[1] will always be the original node
            table.remove(spreads, 1)
            set(pos, air)
        end
        
        local average, leftover = floor(sum / #spreads), sum % #spreads
        
        for i, vec in ipairs(spreads) do
            pos.x, pos.z = pos.x + vec.x, pos.z + vec.z
            local level = average + (i <= leftover and 1 or 0)
            
            if level > 0 then
                setLiquid(pos, flowing, level)
            elseif get(pos).name == flowing then
                set(pos, air)
                update(pos)
            end
            sum = sum - level
            
            pos.x, pos.z = pos.x - vec.x, pos.z - vec.z
        end
        
        --assert(sum == 0)
    end
    
    if liquidDef.bucket then
        extra._waterfinity_bucket = sanitizedBucket
    end
    
    minetest.override_item(flowing, extra)
    
    if bucket and liquidDef.bucket then
        for i = 1, MAX_LVL do
            minetest.register_craftitem(liquidDef.bucket .. (i == MAX_LVL and "" or "_" .. i), {
                description = ("%s (%s/%s)"):format(liquidDef.bucket_desc, i, MAX_LVL),
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
                    local level = getLiquidLevel(pos)
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
                        return ItemStack(sanitizedBucket .. "_" .. MAX_LVL)
                    end
                    
                    local levelTaken = min(level, MAX_LVL - i)
                    if levelTaken == level then
                        set(pos, air)
                    else
                        setLiquidLevel(pos, level - levelTaken)
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
                    local level = getLiquidLevel(lpos)
                    local def = defs[name]
                    local item_count = user:get_wielded_item():get_count()
                    
                    if def._waterfinity_source == name then
                        return ItemStack("bucket:bucket_empty")
                    end
                    
                    local levelGiven = node.name == liquidDef.flowing and min(i, MAX_LVL - level) or i
                    local newLevel = node.name == liquidDef.flowing and level + levelGiven or levelGiven
                    local giveBack = i - levelGiven == 0 and "bucket:bucket_empty" or sanitizedBucket .. "_" .. i - levelGiven
                    
                    setLiquid(lpos, liquidDef.flowing, newLevel)
                    if node.name ~= liquidDef.flowing then
                        return ItemStack("bucket:bucket_empty")
                    end
                    assert(level + i == newLevel + (i - levelGiven))
                    
                    update(lpos)
                    return ItemStack(giveBack)
                end
            })
        end
        
        -- Merge two buckets
        for a = 1, MAX_LVL-1 do
            for b = 1, min(a, MAX_LVL-a) do
                minetest.register_craft {
                    output = liquidDef.bucket.."_"..(a+b),
                    type = "shapeless",
                    recipe = {liquidDef.bucket.."_"..a, liquidDef.bucket.."_"..b},
                    replacements = {
                        {liquidDef.bucket.."_"..a, "bucket:bucket_empty"}
                    }
                }
            end
        end
        
        -- Partition a bucket into min-lvl buckets
        for a = 2, MAX_LVL do
            local recipe = {liquidDef.bucket.."_"..a}
            for i = 1, a-1 do
                recipe[#recipe+1] = "bucket:bucket_empty"
            end
            
            minetest.register_craft {
                output = liquidDef.bucket.."_1 "..a,
                type = "shapeless",
                recipe = recipe
            }
        end
        
        -- Combine three or more min-lvl buckets
        for a = 1, MAX_LVL do
            local recipe, repl = {}, {}
            for i = 1,a do
                recipe[#recipe+1] = liquidDef.bucket.."_1"
                repl[#repl+1] = {liquidDef.bucket.."_1", "bucket:bucket_empty"}
            end
            repl[#repl] = nil
            
            minetest.register_craft {
                output = liquidDef.bucket.."_"..a,
                type = "shapeless",
                recipe = recipe,
                replacements = repl
            }
        end
        
        minetest.register_alias(sanitizedBucket .. "_" .. MAX_LVL, sanitizedBucket)
    end
end

jittercheck = function (pos)
    local myname = get(pos).name
    local mytype = defs[myname]._waterfinity_flowing
    local source = defs[myname]._waterfinity_source
    local mylevel = getLiquidLevel(pos)
    
    pos.y = pos.y-1
    
    local bdef = defs[get(pos).name]
    local below = getLiquidLevel(pos)
    local btype = bdef._waterfinity_flowing
    
    pos.y = pos.y+1
    if below < MAX_LVL and (bdef.floodable or btype == mytype) then return true end
    
    for _, vec in ipairs(cardinals) do
        pos.x, pos.z = pos.x+vec.x, pos.z+vec.z
        
        local level = getLiquidLevel(pos)
        local name = get(pos).name
        local ndef = defs[name]
        local ntype = ndef._waterfinity_flowing
        
        pos.x, pos.z = pos.x-vec.x, pos.z-vec.z
        
        if name == source and mylevel < MAX_LVL then return true end
        if ntype == mytype and abs(level - mylevel) > 1 or ndef.floodable then
            return true
        end
    end
end
if jitterEnabled then
    minetest.register_abm {
        label = "Waterfinity jitter",
        nodenames = {"group:waterfinity_jitter"},
        neighbors = {},
        interval = 1,
        chance = 5,
        catch_up = false,
        action = function (pos, node)
            --minetest.registered_nodes[node.name].on_timer(pos)
            
            local mylvl = getLiquidLevel(pos)
            if mylvl == 8 then
                pos.y = pos.y + 1
                local above = get(pos)
                if above.name == node.name then
                    return
                end
                pos.y = pos.y - 1
            end
            
            local dir = cardinals[random(1, 4)]
            local otherx, otherz = dir.z, dir.x
            if random(1,2) == 1 then
                otherx = -otherx
                otherz = -otherz
            end
            
            local x, z = pos.x, pos.z
            local cx, cz, candlvl = pos.x, pos.z, mylvl
            
            local found = {}
            
            for i = 1, min(10/random(), 100) do
                pos.x, pos.z = pos.x + dir.x, pos.z + dir.z --(choice==1 and otherx or dir.x), pos.z + (choice==1 and otherz or dir.z)
                local neigh = get(pos)
                
                local hash = ("%s,%s"):format(pos.x, pos.z)
                if found[hash] or neigh.name ~= node.name then
                    pos.x, pos.z = pos.x - dir.x + otherx, pos.z - dir.z + otherz
                    hash = ("%s,%s"):format(pos.x, pos.z)
                    neigh = get(pos)
                    
                    if found[hash] or neigh.name ~= node.name then
                        pos.x, pos.z = pos.x - 2*otherx, pos.z - 2*otherz
                        hash = ("%s,%s"):format(pos.x, pos.z)
                        neigh = get(pos)
                    
                        if found[hash] or neigh.name ~= node.name then
                            pos.x, pos.z = pos.x + otherx - dir.x, pos.z + otherz - dir.z
                            hash = ("%s,%s"):format(pos.x, pos.z)
                            neigh = get(pos)
                            
                            if found[hash] or neigh.name ~= node.name then
                                break
                            end
                        end
                    end
                end
                found[hash] = true
                
                local neighlvl = getLiquidLevel(pos)
                
                if neighlvl < candlvl then
                    cx, cz = pos.x, pos.z
                    candlvl = neighlvl
                end
            end
            
            if candlvl < mylvl - 1 then
                local sum = mylvl + candlvl
                local left = 0
                if sum > 8 then
                    left = sum - 8
                    sum = 8
                else
                    sum = sum - 1
                    left = 1
                end
                
                local y = pos.y
                
                pos.x,pos.z = cx,cz
                setLiquidLevel(pos, sum)
                minetest.registered_nodes[node.name].on_timer(pos)
                
                pos.x, pos.y, pos.z = x, y, z
                setLiquidLevel(pos, left)
                minetest.registered_nodes[node.name].on_timer(pos)
                
                return
            end
        end
    }
else
    jittercheck = function () return true end
end

minetest.register_on_dignode(function (pos)
    update(pos)
end)

--[[local getHashPos = minetest.get_position_from_hash
minetest.register_on_mapblocks_changed(function (modified_blocks, modified_block_count)
    for hash, _ in pairs(modified_blocks) do
        local pos = getHashPos(hash)
        
        local node = get(pos)
        local def = defs[node.name] or empty
        local timeout = def._waterfinity_flowing and getTimer(pos):get_timeout() or 0
        
        if timeout == 0 and jittercheck(pos) then
            update(pos)
        end
    end
end)]]

local checkFalling = minetest.check_for_falling
minetest.check_for_falling = function (pos, ...)
    update(pos)
    return checkFalling(pos, ...)
end

local function texturegen(part, full)
    if not full then full = part end
    local textures = {}
    
    for i = 0, 6 do
        table.insert(textures, ("%s^(waterfinity_bucket_bars.png^[sheet:1x8:0,%s)"):format(part, i))
    end
    table.insert(textures, ("%s^(waterfinity_bucket_bars.png^[sheet:1x8:0,7)"):format(full))
    
    return textures
end
waterfinity.bucket_textures = texturegen

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
            liquidDef.bucket_images = texturegen(bucketDef.inventory_image)
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
            setLiquid(pos, flowingAlts[node.name], MAX_LVL)
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
                            paramData[index] = MAX_LVL - 1
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
            for i = 1, MAX_LVL do
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
    local textureStill = "default_water.png^[multiply:#CCCCCC^[opacity:220" -- "waterfinity_spring.png"
    local animStill = "default_water_source_animated.png^[multiply:#CCCCCC^[opacity:220" -- "waterfinity_spring_animated.png"
    local animFlow = "default_water_flowing_animated.png^[multiply:#CCCCCC^[opacity:220" -- "default_water_source_animated.png"
    
    minetest.register_node("waterfinity:water", {
        description = S("Finite Water"),
        tiles = {textureStill},
        special_tiles = {
            {
                name = animStill,
                backface_culling = false,
                animation = {
                    type = "vertical_frames",
                    aspect_w = 16,
                    aspect_h = 16,
                    length = 2,
                }
            },
            {
                name = animFlow,
                backface_culling = true,
                animation = {
                    type = "vertical_frames",
                    aspect_w = 16,
                    aspect_h = 16,
                    length = 0.5,
                }
            },
        },
        
        groups = {liquid = 3, water = 3, cools_lava = 3},
        
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
        
        post_effect_color = {r = 30, g = 60, b = 90, a = 103},
        
        leveled_max = MAX_LVL - 1,
        
        on_blast = function (pos, intensity) end,
        sounds = default.node_sound_water_defaults()
    })
    minetest.register_node("waterfinity:spring", {
        description = S("Finite Water Spring"),
        tiles = {{
            name = animStill,
            backface_culling = false,
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 4,
            },
        }},
        
        groups = {liquid = 3, water = 3, cools_lava = 3},
        
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
        
        post_effect_color = {r = 30, g = 60, b = 90, a = 103},
        
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
        
        groups = {liquid = 3, lava = 3, igniter = 1},
        
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
        
        bucket_images = texturegen("bucket_water.png")-- ("waterfinity_bucket_water_part.png", "waterfinity_bucket_water.png")
    }
    waterfinity.register_liquid {
        flowing = "waterfinity:lava",
        
        drain_range = 0,
        jitter = false,
        
        bucket = "waterfinity:bucket_lava",
        bucket_desc = S("Finite Lava Bucket"),
        bucket_images = texturegen("bucket_lava.png")--("waterfinity_bucket_lava_part.png", "bucket_lava.png")
    }
    
    if bucket then
        for i = 1, MAX_LVL do
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
                            paramData[index] = MAX_LVL - 1
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
            --vm:update_liquids()
        end)
    end
    
    function waterfinity.cool_lava(pos, node)
        if getLiquidLevel(pos) == 7 then
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
            neighbors = {"group:cools_lava"},
            interval = 1,
            chance = 1,
            catch_up = false,
            action = waterfinity.cool_lava,
        }
    end
end

do
    local oldcheck = minetest.check_for_falling
    function minetest.check_for_falling(pos)
        update(pos)
        return oldcheck(pos)
    end
end
do
    local oldcheck = minetest.check_single_for_falling
    function minetest.check_single_for_falling(pos)
        update(pos)
        return oldcheck(pos)
    end
end

if minetest.get_modpath("mesecons") then
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
        local liquid_data = {}
        local frontiers = mesecon.fifo_queue.new()
        frontiers:add(vector.new(pos))

        for np in frontiers:iter() do
            local np_hash = minetest.hash_node_position(np)
            local nn = not pos_set[np_hash] and minetest.get_node(np)
            if nn and not node_replaceable(nn.name) then
                pos_set[np_hash] = true
                table.insert(nodes, {node = nn, pos = np})
                if #nodes > maximum then return nil end

                -- add connected nodes to frontiers
                local nndef = minetest.registered_nodes[nn.name]
                if nndef and nndef.mvps_sticky then
                    local connected = nndef.mvps_sticky(np, nn)
                    for _, cp in ipairs(connected) do
                        frontiers:add(cp)
                    end
                end
                
                -- If liquid, check if this liquid can compress into the previous liquid
                local compress = false
                if defs[nn.name]._waterfinity_flowing == nn.name then
                    local prevhash = minetest.hash_node_position(vector.subtract(np, dir))
                    liquid_data[np_hash] = {name = nn.name, ind = #nodes}
                    
                    if liquid_data[prevhash] and liquid_data[prevhash].name == nn.name then
                        local level, count = liquid_data[prevhash].level + getLiquidLevel(np), liquid_data[prevhash].count + 1
                        
                        if level <= MAX_LVL * (count - 1) then
                            compress = {total = level, count = count - 1}
                        end
                        
                        liquid_data[np_hash].level = level
                        liquid_data[np_hash].count = count
                    else
                        liquid_data[np_hash].level = getLiquidLevel(np)
                        liquid_data[np_hash].count = 1
                    end
                end
                
                if compress then
                    local compp = vector.subtract(np, dir)
                    for i = compress.count, 1, -1 do
                        local comphash = minetest.hash_node_position(compp)
                        nodes[liquid_data[comphash].ind].node.param2 = math.floor(compress.total / compress.count) + (compress.total % compress.count >= i and 1 or 0) - 1
                        compp = vector.subtract(compp, dir)
                    end
                    
                    table.remove(nodes, #nodes)
                else
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
    
    mesecon.register_on_mvps_move(function(moved_nodes)
        for _, data in ipairs(moved_nodes) do
            update(data.oldpos)
            update(data.pos)
        end
    end)
end