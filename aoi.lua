--使用方法可以参考最底下注释掉的测试，算法来自于云风：http://blog.codingnow.com/2012/03/dev_note_13.html

--可视范围的平方
local AOI_RADIS2 = 10000

local DIST2 = function(a,b) 
	return (a[1]-b[1])*(a[1]-b[1])+(a[2]-b[2])*(a[2]-b[2])
end

local function object_new(id)
	local o = {
		id = id,
		version = 0,
		mode = {},
		--last = nil,
		--position = nil,
	}
	return o
end

local function map_query(map, id)
	if not map[id] then
		map[id] = object_new(id)
	end
	return map[id]
end

local function map_foreach(map, func, ud)
	for id, obj in pairs(map) do
		func(ud, obj)
	end
end

local function copy_position(src)
	local rtn = {src[1], src[2], src[3]}
	return rtn
end

local function change_mode(obj, set_watcher, set_marker)
	local change = false
	if obj.mode == nil then
		obj.mode = {}
		if set_watcher then
			obj.mode.MODE_WATCHER = true
		end
		if set_marker then
			obj.mode.MODE_MARKER = true
		end
		return true
	end
	if set_watcher then
		if not obj.mode.MODE_WATCHER then
			obj.mode.MODE_WATCHER = true
			change = true
		end
	else
		if obj.mode.MODE_WATCHER then
			obj.mode.MODE_WATCHER = nil
			change = true
		end
	end
	if set_marker then
		if not obj.mode.MODE_MARKER then
			obj.mode.MODE_MARKER = true
			change = true
		end
	else
		if obj.mode.MODE_MARKER then
			obj.mode.MODE_MARKER = nil
			change = true
		end
	end
	return change
end

local function is_near(p1, p2)
	return DIST2(p1, p2) < AOI_RADIS2 * 0.25
end

local function dist2(obj1, obj2)
	return DIST2(obj1.position, obj2.position)
end

local function aoi_update(aoi_space, id, mode, pos)
	--print("aoi_update", id)
	local obj = map_query(aoi_space.object, id)
	local set_watcher, set_marker = false, false
	for _, m in pairs(mode) do
		if m == "d" then
			if not obj.mode.MODE_DROP then
				obj.mode.MODE_DROP = true
				aoi_space.object[id] = nil
				return
			end
		elseif m == "w" then
			set_watcher = true
		elseif m == "m" then
			set_marker = true
		end	
		if obj.mode.MODE_DROP then
			obj.mode.MODE_DROP = nil
		end
		local change = change_mode(obj, set_watcher, set_marker)
		obj.position = copy_position(pos)
		if change or not is_near(pos, obj.last) then
			obj.last = copy_position(pos)
			obj.mode.MODE_MOVE = true
			obj.version = obj.version + 1
		end
	end
end

local function flush_pair(aoi_space)
	local p = aoi_space.hot
	while p do
		local next = p.next
		if p.watcher.version ~= p.watcher_version or
			p.marker.version ~= p.marker_version or
			p.watcher.mode.MODE_DROP or
			p.marker.mode.MODE_DROP then
			p = next
		else
			local d2 = dist2(p.watcher , p.marker)
			if d2 > AOI_RADIS2 * 4 then
				p = next
			elseif d2 < AOI_RADIS2 then
				aoi_space.cb(p.watcher.id, p.marker.id)
				p = next
			else
				aoi_space.hot = p.next
			end
		end
	end
end

local function set_push(aoi_space, obj)
	local mode = obj.mode
	if mode.MODE_WATCHER then
		if mode.MODE_MOVE then
			table.insert(aoi_space.watcher_move, obj)
			mode.MODE_MOVE = nil
		else
			table.insert(aoi_space.watcher_static , obj)
		end
	end
	if mode.MODE_MARKER then
		if mode.MODE_MOVE then
			table.insert(aoi_space.marker_move, obj)
			mode.MODE_MOVE = nil
		else
			table.insert(aoi_space.marker_static , obj)
		end
	end
end

local function gen_pair(aoi_space, watcher, marker)
	if watcher == marker then
		return
	end
	local d2 = dist2(watcher, marker)
	if d2 < AOI_RADIS2 then
		aoi_space.cb(watcher.id, marker.id)
		return
	end
	if d2 > AOI_RADIS2 * 4 then
		return
	end
	local p = {}
	p.watcher = watcher
	p.marker = marker
	p.watcher_version = watcher.version
	p.marker_version = marker.version
	p.next = aoi_space.hot
	aoi_space.hot = p
end

local function gen_pair_list(aoi_space, watchers, markers)
	for _, w in ipairs(watchers) do
		for _, m in ipairs(markers) do
			gen_pair(aoi_space, w, m)
		end
	end
end

local function aoi_message(aoi_space)
	--print("aoi_message")
	--local t1 = os.clock()
	flush_pair(aoi_space)
	--local t2 = os.clock()
	--print("aoi_message2", t2 - t1)
	aoi_space.watcher_static = {}
	aoi_space.watcher_move = {}
	aoi_space.marker_static = {}
	aoi_space.marker_move = {}
	map_foreach(aoi_space.object, set_push , aoi_space);   
	--local t3 = os.clock()  
	--print("aoi_message3", t3 - t2)   
	gen_pair_list(aoi_space, aoi_space.watcher_static, aoi_space.marker_move)
	gen_pair_list(aoi_space, aoi_space.watcher_move, aoi_space.marker_static)
	gen_pair_list(aoi_space, aoi_space.watcher_move, aoi_space.marker_move)
	--local t4 = os.clock()
	--print("aoi_message4", t4 - t3)
end

local _MT = {
	update = aoi_update,
	message = aoi_message,
}
_MT.__index = _MT

local function aoi_new(cb)
	local aoi_space = {}
	aoi_space.object = {}
	aoi_space.watcher_static = {}
  aoi_space.marker_static = {}
  aoi_space.watcher_move = {}
  aoi_space.marker_move = {}
  aoi_space.hot = nil
  aoi_space.cb = cb
  return setmetatable(aoi_space, _MT)
end

local aoi = setmetatable({new = aoi_new},
  {__call = function(_, ...) return aoi_new(...) end})


--------------------------------------------------------
--以下是测试
-- local MEMBER_MAX = 100
-- local WORLD = {}
-- local ID_MAP = {}
-- for i=1,MEMBER_MAX do
-- 	if not ID_MAP[i] then ID_MAP[i] = {} end
-- end
-- local CHECK = {}
-- for i=1,MEMBER_MAX do
-- 	if not CHECK[i] then CHECK[i] = {} end
-- end

-- function generate_test_result()
-- 	for i=1,MEMBER_MAX do
-- 		if not ID_MAP[i] then ID_MAP[i] = {} end
-- 		for j=1,MEMBER_MAX do
-- 			if (WORLD[i][1] == -1 and WORLD[i][2] == -1) or
-- 				(WORLD[j][1] == -1 and WORLD[j][2] == -1) then
-- 				ID_MAP[i][j] = nil
-- 			else
-- 				ID_MAP[i][j] = DIST2(WORLD[i], WORLD[j])
-- 			end
-- 		end
-- 	end
-- end

-- function test_result()
-- 	for i=1,MEMBER_MAX do
-- 		for j=1,MEMBER_MAX do
-- 			local d2 = ID_MAP[i][j]
-- 			if i ~= j and d2 and d2 < AOI_RADIS2 then
-- 				if CHECK[i][j] then
-- 					--print("test", i, j, "OK")
-- 				else
-- 					print("test", i, j, "Failed")
-- 					return false
-- 				end
-- 			end
-- 		end
-- 	end
-- 	return true
-- end

-- local a = aoi(
-- 	function(watcher, marker) 
-- 		if ID_MAP[watcher][marker] < AOI_RADIS2 then
-- 			CHECK[watcher][marker] = true
-- 		else
-- 			error("wrong callback")
-- 		end
-- 	end
-- )

-- local in_map = {}
-- for tick=1,100 do
-- 	--print("tick", tick)
-- 	local t1 = os.clock()
-- 	for i=1,MEMBER_MAX do
-- 		local r = math.random()
-- 		if r < 0.1 and tick > 1 and in_map[i] then
-- 			--print("-------id:", i, "mode:", "d")
-- 			a:update(i, {"d"}, {0,0})
-- 			in_map[i] = nil
-- 			WORLD[i] = {-1, -1}
-- 		else
-- 			local x, y = math.random(0,1000), math.random(0,1000)
-- 			a:update(i, {"w","m"}, {x,y})
-- 			in_map[i] = true
-- 			WORLD[i] = {x, y}
-- 			--print("-------id:", i, "mode:", "mw", "x:", x, "y", y)
-- 		end
-- 	end
-- 	--local t2 = os.clock()
-- 	--print("tick", tick, "move", t2 - t1)
-- 	generate_test_result()
-- 	a:message()
-- 	if not test_result() then
-- 		error("test failed")
-- 	end
-- 	--print("tick", tick, os.clock() - t1)
-- end

return aoi
