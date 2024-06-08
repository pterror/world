local mod = {}

--[[@class text_game: {objects:unknown[]}]]

mod.null = {}
mod.metatable_symbol = {}
mod.properties_metatable_symbol = {}

local function_metatable = {}
function_metatable.__call = function(self, ...)
	return self.function_(...)
end

--[[@param x unknown]]
local is_function = function(x) return getmetatable(x) == function_metatable end

--[[@param source string]]
mod.function_ = function(source)
	return setmetatable({ source = source, function_ = loadstring("return " .. source)() }, function_metatable)
end

--[[@param metatable unknown]]
local is_properties_metatable = function(metatable)
	return type(metatable) == "table" and metatable[mod.properties_metatable_symbol] == true
end

--[[@param context table]]
--[[@param parent? table]]
--[[@param getters? table]]
--[[@param setters? table]]
local properties_metatable = function(context, parent, getters, setters)
	return {
		[mod.properties_metatable_symbol] = true,
		parent = parent,
		getters = getters,
		setters = setters,
		__index = function(target, key)
			if getters and getters[key] then
				return getters[key](target, context)
			else
				return parent and parent[key]
			end
		end,
		__newindex = function(target, key, value)
			if setters and setters[key] then
				setters[key](target, value, context)
			else
				rawset(target, key, value)
			end
		end,
	}
end

mod.define_properties = function(context, base, parent, getters, setters)
	return setmetatable(base, properties_metatable(context, parent, getters, setters))
end

local make_context = function(path)
	local obj = {}
	obj.null = mod.null
	obj.function_ = mod.function_
	obj.define_properties = function(...) return mod.define_properties(obj, ...) end
	--[[@param backup? boolean]]
	obj.save = function(backup) mod.save(path, obj.game, backup) end
	obj.new_object = function(val)
		val = val or {}
		obj.game.objects[#obj.game.objects + 1] = val or {}
		return val
	end
	return obj
end

local replacements = { ["\r"] = "\\r", ["\n"] = "\\n", ["\t"] = "\\t", ["\""] = "\\\"" }

--[[@param s string]]
local escape = function(s) return s:gsub("[\r\n\t\"]", replacements) end

--[[@param s string]]
local escape_raw = function(s)
	local count = 0
	while true do
		local end_delimiter = "]" .. ("="):rep(count) .. "]"
		if not s:find(end_delimiter) then break end
		count = count + 1
	end
	local equals = ("="):rep(count)
	return "[" .. equals .. "[" .. s .. "]" .. equals .. "]"
end

local is_keyword = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}

--[[@param k string|number]]
local as_key = function(k)
	if type(k) ~= "string" then return "[" .. tostring(k) .. "]" end
	local escaped = escape(k)
	if escaped == k and not k:find("%s") and not is_keyword[k] then return k else return "[\"" .. escaped .. "\"]" end
end

local write_object
local return_true = function() return true end

local pretty_print = function(val, write)
	write = write or function(...) io.stdout:write(...) end
	if type(val) ~= "table" then
		write(tostring(val))
	else
		write_object(val, write)
	end
end

local write_object_without_metatable
write_object_without_metatable = function(object, write, on_write_table, should_write_table, data) --[[@param object table]]
	on_write_table = on_write_table or function(v) write_object(v, write, on_write_table, should_write_table, data) end
	should_write_table = should_write_table or return_true
	write("{ ")
	local length = #object
	for k, v in pairs(object) do
		if type(v) ~= "table" or is_function(v) or should_write_table(v, k, data) then
			if type(k) ~= "number" or k > length then write(as_key(k), " = ") end
			if type(v) == "string" then
				write("\"", escape(v), "\"")
			elseif is_function(v) then
				write("ctx.function_(", escape_raw(v.source), ")")
			elseif type(v) ~= "table" then
				write(tostring(v))
			else
				on_write_table(v)
			end
			write(", ")
		end
	end
	write("}")
end

--[[@param object table]]
write_object = function(object, write, on_write_table, should_write_table, data)
	on_write_table = on_write_table or function(v) write_object(v, write, on_write_table, should_write_table, data) end
	should_write_table = should_write_table or return_true
	local metatable = getmetatable(object) --[[@type table?]]
	if metatable and not should_write_table(metatable, mod.metatable_symbol, data) then metatable = nil end
	if metatable then write("setmetatable(") end
	write_object_without_metatable(object, write, on_write_table, should_write_table, data)
	if metatable then
		write(", ")
		on_write_table(metatable)
		write(")")
	end
end

--[[@param path string]]
mod.load = function(path)
	local contents; do
		local file = assert(io.open(path, "r"))
		contents = file:read("*all")
		file:close()
	end
	return loadstring(contents)()(make_context(path))
end

--[[@param path string]]
--[[@param game text_game]]
mod.save_internal = function(path, game)
	local file = assert(io.open(path, "w"))
	local write = function(...) file:write(...) end
	local object_lookup = {} --[[@type table<table, integer>]]
	for i, v in ipairs(game.objects) do object_lookup[v] = i end
	local nested_object_lookup = {} --[[@type table<table, integer>]]
	local nested_objects = {} --[[@type table[] ]]
	local nested_object_count = 0
	local process_object
	local process_value = function(v)
		if type(v) == "table" and not is_function(v) and not object_lookup[v] then
			local old_i = nested_object_lookup[v]
			if old_i then nested_objects[old_i] = nil end
			nested_object_count = nested_object_count + 1
			local i = nested_object_count
			nested_objects[i] = v
			nested_object_lookup[v] = i
			process_object(v)
		end
	end
	process_object = function(object) --[[@param object table]]
		for _, v in pairs(object) do process_value(v) end
		local metatable = getmetatable(object)
		if type(metatable) == "table" then
			if is_properties_metatable(metatable) then
				process_value(metatable.parent)
				process_value(metatable.getters)
				process_value(metatable.setters)
			else
				process_value(metatable)
			end
		end
	end
	for _, object in ipairs(game.objects) do process_object(object) end
	do --[[remove nils from nested_objects]]
		local i = 1
		for j = 1, nested_object_count do
			if nested_objects[j] then
				if i ~= j then
					nested_objects[i] = nested_objects[j]
					nested_objects[j] = nil
				end
				i = i + 1
			end
		end
	end
	local nested_end = #nested_objects + 1
	nested_object_lookup = {} --[[update indices based on compacted array]]
	for i, v in ipairs(nested_objects) do nested_object_lookup[v] = i end

	local extra_statements = {} --[[@type string[] ]]
	local should_write_table = function(v, k, data)
		if nested_object_lookup[v] then return true end
		local i = object_lookup[v]
		if i then
			if k == mod.metatable_symbol then
				extra_statements[#extra_statements + 1] = data.self ..
						" = setmetatable(" .. data.self .. ", objects[" .. i .. "])"
			else
				local key = as_key(k)
				if key:byte(1) ~= 91 --[[ [ ]] then key = "." .. key end
				extra_statements[#extra_statements + 1] = data.self .. key .. " = objects[" .. i .. "]"
			end
			return false
		end
		if k == mod.metatable_symbol and is_properties_metatable(v) then
			local obj_to_string = function(obj)
				if not obj then return "nil" end
				local i2 = nested_object_lookup[obj]
				if i2 then return "nested[" .. (nested_end - i2) .. "]" end
				i2 = object_lookup[v]
				if i2 then return "objects[" .. i2 .. "]" end
				return "nil"
			end
			extra_statements[#extra_statements + 1] = data.self ..
					" = ctx.define_properties(" ..
					data.self ..
					", " .. obj_to_string(v.parent) .. ", " .. obj_to_string(v.getters) .. ", " .. obj_to_string(v.setters) .. ")"
			return false
		end
		return true
	end
	local on_write_table = function(v)
		local rev_i = nested_end - nested_object_lookup[v]
		write("nested[", rev_i, "]")
	end

	--[[FIXME: minimize using nested objects when possible]]
	write("return function(ctx)\n")
	write("\tlocal nested = {}\n")
	write("\tlocal objects = {}\n")
	write("\tlocal game = { objects = objects, }\n")
	write("\tctx.game = game\n")
	for i = 1, #nested_objects do
		local rev_i = nested_end - i
		write("\tnested[", i, "] = ")
		write_object(nested_objects[rev_i], write, on_write_table, should_write_table, { self = "nested[" .. i .. "]" })
		write("\n")
		i = i + 1
	end
	for i, object in ipairs(game.objects) do
		write("\tobjects[", i, "] = ")
		write_object(object, write, on_write_table, should_write_table, { self = "objects[" .. i .. "]" })
		write("\n")
	end
	for _, statement in ipairs(extra_statements) do
		write("\t", statement, "\n")
	end
	write("\treturn ctx\n")
	write("end\n")
	file:close()
end

--[[@param path string]]
--[[@param game text_game]]
--[[@param backup? boolean]]
mod.save = function(path, game, backup)
	if backup ~= false then
		assert(os.rename(path, path .. ".bak"))
	end
	local success, err = pcall(mod.save_internal, path, game)
	if not success then
		os.remove(path)
		error(err)
	end
end

mod.new_game = function() return { objects = {} } end

local normalize_command = { x = "exit", h = "help" }

if pcall(debug.getlocal, 4, 1) then
	return mod
else
	local path = arg[1]
	local success, ctx = pcall(mod.load, path)
	if not success then
		local game = mod.new_game()
		mod.save(path, game)
		success, ctx = pcall(mod.load, path)
	end
	_G.pretty_print = pretty_print
	for k, v in pairs(ctx) do _G[k] = v end
	for k, v in pairs(ctx.game) do _G[k] = v end
	while true do
		io.stdout:write("text_game> ")
		local input = tostring(io.stdin:read("line"))
		if input:byte(1) == 46 --[[.]] then
			input = input:sub(2)
			input = normalize_command[input] or input
			if input == "exit" then
				break
			elseif input == "help" then
				print([[
commands:
h, help - show this help screen
e, exit - exit the repl

lua context:
game - full game state
  game.objects - list of objects
null - a non-nil "null" value, so that it shows up when iterating keys
object - game.objects
save() - saves game to the path from which it was loaded
new_object(val = {}) - add a new object to the list of objects
define_properties(val, parent = nil, getters = nil, setters = nil) - add getters and setters to an object]])
			else
				io.stderr:write("error: unknown command\n")
			end
		end
		if input:byte(1) == 59 --[[;]] then
			input = input:sub(2)
		else
			input = "return " .. input
		end
		local chunk, err = loadstring(input)
		if not chunk then
			io.stderr:write("error: invalid code: ", err, "\n")
		else
			local success2, ret = pcall(chunk)
			if not success2 then
				io.stderr:write("error: panic running code: ", ret, "\n")
			elseif ret ~= nil then
				pretty_print(ret)
				io.stdout:write("\n")
			end
		end
	end
end

--[[FIXME:
printf 'save()\n.exit' | rlwrap luajit text_game.lua games/pterror.lua

this command causes the repl to enter an infinite loop
exiting on empty input is far from an ideal solution
]]
--[[TODO: mostly working, but `.description` is not working because `target` is not the correct object...]]
--[[TODO: unnest `nested[]` tables when possible]]
--[[TODO: test `a = {}; a.a = a; a.b = a` - esp. for objects]]
--[[TODO:
- properly implement ctx.define_properties
- implement codegen for define_properties (requires detection for it as well)
	- also decide on an order for define_properties vs setmetatable
		- setmetatable is still desired because it may have e.g. __call
- basic output (ansi codes)
]]
--[[
- future output formats:
	- quantization to 256 color ansi (and possibly lower)
	- html (needs http and/or ws server)
	- qt? (needs to be able to be run from qml?)
]]
