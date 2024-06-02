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

local ctx = function(path)
	local obj = {}
	obj.function_ = mod.function_
	obj.save = function() mod.save(path, obj.game) end
	return obj
end

--[[@param path string]]
mod.load = function(path)
	local contents; do
		local file = assert(io.open(path, "r"))
		contents = file:read("*all")
		file:close()
	end
	return loadstring(contents)()(ctx(path))
end

local replacements = { ["\r"] = "\\r", ["\n"] = "\\n", ["\t"] = "\\t", ["\""] = "\\\"" }

--[[@param s string]]
local escape = function(s) return s:gsub("[\r\n\t\"]", replacements) end

--[[@param k string|number]]
local as_key = function(k)
	if type(k) ~= "string" then return "[" .. k .. "]" end
	local escaped = escape(k)
	if escaped == k then return k else return "[\"" .. escaped .. "\"]" end
end

--[[@param path string]]
--[[@param game text_game]]
mod.save = function(path, game)
	local file = assert(io.open(path, "w"))
	local nested_object_lookup = {} --[[@type table<table, integer>]]
	local nested_objects = {} --[[@type table[] ]]
	local process_object
	process_object = function(object) --[[@param object table]]
		for _, v in pairs(object) do
			if type(v) == "table" and not is_function(v) then
				if not nested_object_lookup[v] then
					local i = #nested_objects + 1
					nested_objects[i] = v
					nested_object_lookup[v] = i
					process_object(v)
				end
			end
		end
	end
	for _, object in ipairs(game.objects) do process_object(object) end
	local nested_end = #nested_objects + 1

	local write_object = function(object) --[[@param object table]]
		file:write("{ ")
		local length = #object
		for k, v in pairs(object) do
			if type(k) ~= "number" or k > length then file:write(as_key(k), " = ") end
			if type(v) == "string" then
				file:write("\"", escape(v), "\"")
			elseif is_function(v) then
				file:write("ctx.function_(\"", escape(v.source), "\")")
			elseif type(v) ~= "table" then
				file:write(tostring(v))
			else
				local rev_i = nested_end - nested_object_lookup[v]
				file:write("nested[", rev_i, "]")
			end
			file:write(", ")
		end
		file:write("}\n")
	end

	file:write("return function(ctx)\n")
	file:write("\tlocal nested = {}\n")
	file:write("\tlocal objects = {}\n")
	file:write("\tlocal game = { objects = objects, }\n")
	file:write("\tctx.game = game\n")
	for i = 1, #nested_objects do
		local rev_i = nested_end - i
		file:write("\tnested[", i, "] = ")
		write_object(nested_objects[rev_i])
		i = i + 1
	end
	for i, object in ipairs(game.objects) do
		file:write("\tobjects[", i, "] = ")
		write_object(object)
	end
	file:write("\treturn ctx\n")
	file:write("end\n")
	file:close()
end

if pcall(debug.getlocal, 4, 1) then
	return mod
else
	local filename = arg[1]
	if false then
		local x = { c = 1, d = "owo", e = false }
		local game = {
			objects = { {
				a = 1,
				b = { x, x },
				c = mod.function_("function (_, foo) return foo + 1 end"),
				d = {},
				e = mod.function_(
					"function (ctx) ctx.game.objects[2] = { 3, 4 }; ctx.save(); ctx.game.objects[3] = { 3, true }; ctx.save() end"),
			} }
		}
		print("should be 2:", game.objects[1].c(nil, 1))
		mod.save("test.lua", game)
		local ctx2 = mod.load("test.lua")
		local game2 = ctx2.game
		print("should be 2:", game2.objects[1].c(nil, 1))
		game2.objects[1].e(ctx2)
	end
	--[[FIXME: run main]]
end
