local mod = {}

--[[@class text_game: {objects:unknown[]}]]

local io = io
local os = os
_G.io = nil
_G.os = nil

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

--[[@param context table]]
--[[@param object table]]
local smart_object_metatable = function(context, object)
	return {
		__index = function(_, key)
			local value = object[key]
			if value then return value end
			local getter = object["get " .. key]
			if getter then return getter(object, context) end
		end,
		__newindex = function(_, key, value)
			if object[key] then
				object[key] = value
				return
			end
			local setter = object["set " .. key]
			if setter then
				setter(object, value, context)
				return
			end
			object[key] = value
		end,
	}
end

local make_context = function(path, opts)
	opts = opts or {}
	local context = {}
	local smart_object_cache = setmetatable({}, { __mode = "k" })
	local make_smart_object = function(v)
		local smart_object = smart_object_cache[v]
		if not smart_object then
			--[[first arg must not be v, because we do not want to set the metatable of v itself]]
			smart_object = setmetatable({}, smart_object_metatable(context, v))
			smart_object_cache[v] = smart_object
		end
		return smart_object
	end
	context.ui = type(opts.ui) == "table" and opts.ui or type(opts.ui) == "string" or mod.ui[opts.ui] or mod.ui.ansi
	context.objects = setmetatable({},
		{ __index = function(_, k) return make_smart_object(context.game.objects[k]) end })
	context.null = mod.null
	context.function_ = mod.function_
	--[[@param backup? boolean]]
	context.save = function(backup) mod.save(path, context.game, backup) end
	context.new_object = function(val)
		val = val or {}
		context.game.objects[#context.game.objects + 1] = val or {}
		return val
	end
	return context
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
	on_write_table = on_write_table or
			function(v, _, data2) write_object(v, write, on_write_table, should_write_table, data2) end
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
				on_write_table(v, k, data)
			end
			write(", ")
		end
	end
	write("}")
end

--[[@param object table]]
write_object = function(object, write, on_write_table, should_write_table, data)
	on_write_table = on_write_table or
			function(v, _, data2) write_object(v, write, on_write_table, should_write_table, data2) end
	should_write_table = should_write_table or return_true
	local metatable = getmetatable(object) --[[@type table?]]
	if metatable and not should_write_table(metatable, mod.metatable_symbol, data) then metatable = nil end
	if metatable then write("setmetatable(") end
	write_object_without_metatable(object, write, on_write_table, should_write_table, data)
	if metatable then
		write(", ")
		on_write_table(metatable, mod.metatable_symbol, data)
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
	local nested_object_counts = {} --[[@type table<table, integer>]]
	local nested_objects = {} --[[@type table[] ]]
	local nested_object_count = 0
	local process_object
	local process_value = function(v)
		if type(v) == "table" and not is_function(v) and not object_lookup[v] then
			local old_count = nested_object_counts[v]
			nested_object_counts[v] = (old_count or 0) + 1
			if not old_count then
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
	process_object = function(object) --[[@param object table]]
		for _, v in pairs(object) do process_value(v) end
		local metatable = getmetatable(object)
		if type(metatable) == "table" then
			process_value(metatable)
		end
	end
	for _, object in ipairs(game.objects) do process_object(object) end
	do --[[remove nils from nested_objects]]
		local new_nested_objects = {}
		for j = 1, nested_object_count do
			local v = nested_objects[j]
			if v and nested_object_counts[v] > 1 then
				new_nested_objects[#new_nested_objects + 1] = v
			end
		end
		nested_objects = new_nested_objects
		--[[@diagnostic disable-next-line: cast-local-type]]
		nested_object_counts = nil
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
		return true
	end
	local on_write_table
	on_write_table = function(v, k, data)
		local i = nested_object_lookup[v]
		if i then
			local rev_i = nested_end - i
			write("nested[", rev_i, "]")
			return
		end
		local self = data.self
		if k == mod.metatable_symbol then
			self = "getmetatable(" .. self .. ")"
		else
			local key = as_key(k)
			if key:byte(1) ~= 91 --[[ [ ]] then key = "." .. key end
			self = self .. key
		end
		write_object(v, write, on_write_table, should_write_table, { self = self })
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
		local file = io.open(path)
		if file then
			file:close()
			assert(os.rename(path, path .. ".bak"))
		end
	end
	local success, err = pcall(mod.save_internal, path, game)
	if not success then
		os.remove(path)
		io.stderr:write(err, "\n")
	end
end

mod.new_game = function() return { objects = {} } end

--[[@param parts string[] ]]
local join_with_blank = function(parts) return table.concat(parts, "") end
--[[@param parts string[] ]]
local join_with_space = function(parts) return table.concat(parts, " ") end

mod.ui = {}
local ui = mod.ui

ui.plain_text = {}
local plain_text_ui = mod.ui.plain_text
plain_text_ui.container = join_with_space
plain_text_ui.sentence = join_with_blank
plain_text_ui.color = join_with_blank

--[[ansi support for 8/16/256 colors can come later, quantization is hard]]
ui.ansi = {}
local ansi_ui = mod.ui.ansi
ansi_ui.container = join_with_space
ansi_ui.sentence = join_with_blank
local truecolor_colorspace_processor = {}
truecolor_colorspace_processor.rgb = function(t)
	return "\x1b[38;2;" ..
			math.floor(t.red or 0) .. ";" .. math.floor(t.green or 0) .. ";" .. math.floor(t.blue or 0) .. "m"
end
ansi_ui.color = function(table)
	local text = join_with_blank(table)
	local processor = truecolor_colorspace_processor[table.space]
	if processor and table.color then
		--[[TODO: keep a stack of formatting info, when an inner `color` ends the outer `color` should still apply]]
		text = processor(table.color) .. text .. "\x1b[0m"
	end
	return text
end

--[[needs http and/or ws server to actually work since it needs to connect to the lua process]]
ui.html = {}
local html_ui = mod.ui.html
html_ui.container = join_with_space
html_ui.sentence = join_with_blank
local css_colorspace_processor = {}
local css_colorspace_alpha = function(alpha)
	if not alpha or alpha == 1 then return "" end
	return " / " .. alpha
end
css_colorspace_processor.rgb = function(t)
	return "rgb(" ..
			(t.red or 0) .. " " .. (t.green or 0) .. " " .. (t.blue or 0) .. css_colorspace_alpha(t.alpha) .. ")"
end
css_colorspace_processor.lch = function(t)
	return "lch(" ..
			(t.lightness or 0) .. " " .. (t.chroma or 0) .. " " .. (t.hue or 0) .. css_colorspace_alpha(t.alpha) .. ")"
end
css_colorspace_processor.lab = function(t)
	return "lab(" ..
			(t.lightness or 0) .. " " .. (t.a or 0) .. " " .. (t.b or 0) .. css_colorspace_alpha(t.alpha) .. ")"
end
css_colorspace_processor.oklch = function(t)
	return "oklch(" ..
			(t.lightness or 0) .. " " .. (t.chroma or 0) .. " " .. (t.hue or 0) .. css_colorspace_alpha(t.alpha) .. ")"
end
css_colorspace_processor.oklab = function(t)
	return "oklab(" ..
			(t.lightness or 0) .. " " .. (t.a or 0) .. " " .. (t.b or 0) .. css_colorspace_alpha(t.alpha) .. ")"
end
css_colorspace_processor.hsl = function(t)
	return "hwb(" ..
			(t.hue or 0) .. " " .. (t.saturation or 0) .. " " .. (t.lightness or 0) .. css_colorspace_alpha(t.alpha) .. ")"
end
css_colorspace_processor.hwb = function(t)
	return "hwb(" ..
			(t.hue or 0) .. " " .. (t.whiteness or 0) .. " " .. (t.blackness or 0) .. css_colorspace_alpha(t.alpha) .. ")"
end
html_ui.color = function(table)
	local text = join_with_blank(table)
	local processor = css_colorspace_processor[table.space]
	if processor and table.color then
		text = "<span style=\"color: " .. processor(table.color) .. "\">" .. text .. "</span>"
	end
	return text
end

local normalize_command = { x = "exit", h = "help" }

if pcall(debug.getlocal, 4, 1) then
	return mod
else
	local path = arg[1]
	local success, ctx = pcall(mod.load, path)
	if not success then
		if ctx:find("No such file or directory$") then
			local game = mod.new_game()
			mod.save(path, game)
			success, ctx = pcall(mod.load, path)
		else
			error(ctx)
		end
	end
	do
		local ui_renderer = os.getenv("TG_UI")
		if ui_renderer then ctx.ui = mod.ui[ui_renderer] end
	end
	_G.pretty_print = pretty_print
	for k, v in pairs(ctx) do _G[k] = v end
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
printf 'save()' | rlwrap luajit text_game.lua games/pterror.lua

this command causes the repl to enter an infinite loop
exiting on empty input is far from an ideal solution
]]
--[[TODO: test `a = {}; a.a = a; a.b = a` - esp. for objects]]
--[[
- future output formats:
	- qt? (needs to be able to run lua from qml)
		- i don't think this thing needs to access anything special so embedding luajit as a qt plugin should be enough
			- will be slow on mobile though
]]
--[[
next steps:
- moving around rooms
- interacting with (mutating) rooms
- inventory
- eating
- verbs/cli
]]
--[[
low priority (taking features from lambdamoo):
- permission controls - check for sandbox escapes
- hashing for passwords
]]
