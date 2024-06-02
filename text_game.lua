local mod = {}

--[[@class text_game: {objects:unknown[]}]]

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

local replacements = { ["\r"] = "\\r", ["\n"] = "\\n", ["\t"] = "\\t", ["\""] = "\\\"" }

--[[@param s string]]
local escape = function(s) return s:gsub("[\r\n\t\"]", replacements) end

--[[@param k string|number]]
local as_key = function(k)
	if type(k) ~= "string" then return "[" .. k .. "]" end
	local escaped = escape(k)
	if escaped == k and not k:find("%s") then return k else return "[\"" .. escaped .. "\"]" end
end

local write_object
write_object = function(object, write, on_write_table) --[[@param object table]]
	on_write_table = on_write_table or function(v) write_object(v, write) end
	write("{ ")
	local length = #object
	for k, v in pairs(object) do
		if type(k) ~= "number" or k > length then write(as_key(k), " = ") end
		if type(v) == "string" then
			write("\"", escape(v), "\"")
		elseif is_function(v) then
			write("ctx.function_(\"", escape(v.source), "\")")
		elseif type(v) ~= "table" then
			write(tostring(v))
		else
			on_write_table(v)
		end
		write(", ")
	end
	write("}")
end

local pretty_print = function(val, write)
	write = write or function(...) io.stdout:write(...) end
	if type(val) ~= "table" then
		write(tostring(val))
	else
		write_object(val, write)
	end
end

local make_ctx = function(path)
	local obj = {}
	obj.function_ = mod.function_
	obj.save = function() mod.save(path, obj.game) end
	obj.new_object = function(val)
		val = val or {}
		obj.game.objects[#obj.game.objects + 1] = val or {}
		return val
	end
	return obj
end

--[[@param path string]]
mod.load = function(path)
	local contents; do
		local file = assert(io.open(path, "r"))
		contents = file:read("*all")
		file:close()
	end
	return loadstring(contents)()(make_ctx(path))
end

--[[@param path string]]
--[[@param game text_game]]
mod.save = function(path, game)
	local file = assert(io.open(path, "w"))
	local write = function(...) file:write(...) end
	local nested_object_lookup = {} --[[@type table<table, integer>]]
	local nested_objects = {} --[[@type table[] ]]
	local nested_object_count = 0
	local process_object
	process_object = function(object) --[[@param object table]]
		for _, v in pairs(object) do
			if type(v) == "table" and not is_function(v) then
				local old_i = nested_object_lookup[v]
				if old_i then nested_objects[old_i] = nil end
				nested_object_count = nested_object_count + 1
				local i = nested_object_count
				nested_objects[i] = v
				nested_object_lookup[v] = i
				process_object(v)
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

	local on_write_table = function(v)
		local rev_i = nested_end - nested_object_lookup[v]
		write("nested[", rev_i, "]")
	end

	write("return function(ctx)\n")
	write("\tlocal nested = {}\n")
	write("\tlocal objects = {}\n")
	write("\tlocal game = { objects = objects, }\n")
	write("\tctx.game = game\n")
	for i = 1, #nested_objects do
		local rev_i = nested_end - i
		write("\tnested[", i, "] = ")
		write_object(nested_objects[rev_i], write, on_write_table)
		write("\n")
		i = i + 1
	end
	for i, object in ipairs(game.objects) do
		write("\tobjects[", i, "] = ")
		write_object(object, write, on_write_table)
		write("\n")
	end
	write("\treturn ctx\n")
	write("end\n")
	file:close()
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
commands: x exit h help
lua context:
game - full game state
  game.objects - list of objects
object - game.objects
save() - saves game to the path from which it was loaded
new_object(val = {}) - add a new object to the list of objects]])
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
--[[TODO: lazy proxy around objects so they can reference other objects?]]
