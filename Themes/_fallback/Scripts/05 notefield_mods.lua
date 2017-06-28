-- The mod system's sin/cos functions multiply by pi internally, but these
-- mods ported from ITG weren't made with pi in mind.
-- So divide by pi before sin or cos.
local function pi_div(equation)
	return {'*', 1/math.pi, equation}
end

local function offset(time, offset)
	if offset == 0 then return time
	else return {'+', time, offset}
	end
end

-- operators are considered interchangeable if they have the same number of
-- operands.
local arg_counts= {
	['%']= 2,
	['mod']= 2,
	['o']= 2,
	['round']= 2,
	['_']= 2,
	['floor']= 2,
	['ceil']= 2,
	['sin']= 1,
	['cos']= 1,
	['tan']= 1,
	['square']= 1,
	['triangle']= 1,
	['random']= 1,
	['repeat']= 3,
}

local function check_op(eq)
	local op= eq[1]
	local count= arg_counts[op]
	if not count or count+1 == #eq then
		return eq
	end
	assert(false, "Wrong number of operands.  "..op.." requires exactly "..count.." but there are "..(#eq-1))
end

local engine_custom_mods= {
	-- Each entry is a base mod equation and a set of parameters.
	beat= {
		target= 'note_pos_x',
		equation= function(params, ops)
			local time_wave_input= offset(params.time, params.time_offset)
			-- triangle wave - n results in the section above zero having width 1-n
			-- so triangle - (1-w) will give us width w
			-- time_wave_input is doubled and offset to put a peak on every beat.
			local triangle= {'triangle', {'+', .5, {'*', 2, time_wave_input}}}
			local above_zero_is_width= {'-', triangle, {'-', 1, params.width}}
			-- height above zero needs to be 1, but is currently w.
			-- <result> / w will make the height 1
			local height_is_one= {'/', above_zero_is_width, params.width}
			-- then max is used to clip off the parts of the wave that are below
			-- zero, and we have a wave that is flat between peaks.
			local beat_wave= {'max', 0, height_is_one}
			local curved_wave= {'^', beat_wave, 2}
			-- inverter has peaks on even beats, and troughs on odd beats, to make
			-- the motion alternate directions.
			local inverter= {'square', {'+', .5, time_wave_input}}
			local time_beat_factor= {'*', curved_wave, 20, inverter}
			local note_beat_factor= {
				ops.wave,
				{'+', params.wave_offset,
				 {'/',
					params.note_input,
					params.period,
				 },
				},
			}
			local time_and_beat= check_op{ops.factor, time_beat_factor, note_beat_factor}
			return check_op{ops.level, params.level, time_and_beat}
		end,
		params= {
			level= 1, note_input= 'y_offset', wave_offset= .5, period= 6,
			time= 'music_beat', width= .5,
		},
		ops= {
			level= '*', factor= '*', wave= 'sin',
		},
		examples= {
			{"beat twice as hard", "'beat', {level= {mult= 2}}"},
			{"beat twice as often", "'beat', {time= {mult= 2}}"},
			{"beat with longer ramp time", "'beat', {width= {mult= 2}}"},
		}
	},
	blink= {
		target= 'note_alpha',
		equation= function(params, ops)
			return check_op{
				ops.level,
				check_op{
					ops.round,
					check_op{
						ops.wave,
						check_op{ops.input, offset(params.input, params.offset), 10, params.level}
					},
					params.round,
				},
				1,
			}
		end,
		params= {
			input= 'music_second', level= 1, offset= 0,
		},
		ops= {
			level= '-', round= 'round', wave= 'sin', input= '*',
		},
	},
	bumpy= {
		target= 'note_pos_z',
		equation= function(params, ops)
			return check_op{
				ops.level, 40, params.level,
				check_op{
					ops.wave,
					check_op{ops.input, offset(params.input, params.offset), 1/16},
				},
			}
		end,
		params= {
			level= 1, input= 'y_offset', offset= 0,
		},
		ops= {
			level= '*', wave= 'sin', input= '*',
		},
	},
	confusion= {
		target= 'note_rot_z',
		equation= function(params, ops)
			return check_op{ops.level, offset(params.input, params.offset), params.level, 2*math.pi}
		end,
		params= {
			input= 'music_beat', level= 1, offset= 0,
		},
		ops= {
			level= '*',
		},
	},
	dizzy= {
		target= 'note_rot_z',
		equation= function(params, ops)
			return check_op{ops.level, offset(params.input, params.offset), params.level}
		end,
		params= {
			input= 'dist_beat', level= 1, offset= 0,
		},
		ops= {
			level= '*',
		},
	},
	stealth= {
		target= 'note_alpha',
		equation= function(params, ops)
			return {ops.level, params.offset, params.level}
		end,
		params= {
			level= 1, offset= 1,
		},
		ops= {
			level= '-',
		},
	},
	drunk= {
		target= 'note_pos_x',
		equation= function(params, ops)
			return check_op{
				ops.level, params.level, 32,
				check_op{
					ops.wave,
					pi_div{
						ops.time, params.time,
						{ops.column, params.column_input, .2},
						{ops.input, params.input, 10, 1/480},
					},
				},
			}
		end,
		params= {
			level= 1, time= 'music_second', column= 'column', input= 'y_offset',
		},
		ops= {
			level= '*', wave= 'cos', time= '+', column= '*', input= '*',
		},
		examples= {
			{"normal drunk", "'drunk'"},
			{"beat based drunk instead second based drunk", "'drunk', {time= 'music_beat'}"},
			{"tan drunk", "'drunk', {}, {wave= 'tan'}"},
		},
	},
}

local function tune_params(params, defaults)
	if type(params) == "table" then
		add_defaults_to_params(params, defaults)
		return params
	else
		return defaults
	end
end

local function sanity_check_custom_mods(mods)
	for name, mod in pairs(mods) do
		add_blank_tables_to_params(mod, {"params", "ops", "examples"})
	end
end

local theme_custom_mods= {}

function set_theme_custom_mods(mods)
	if type(mods) ~= "table" then mods= {} end
	theme_custom_mods= mods
end

local simfile_custom_mods= {}

function set_simfile_custom_mods(mods)
	if type(mods) ~= "table" then mods= {} end
	simfile_custom_mods= mods
end

local function print_params_info(name, params)
	local has_none= true
	for name, meh in pairs(params) do
		has_none= false
		break
	end
	if has_none then
		Trace("    "..name..":  None.")
	else
		Trace("    "..name..":")
		foreach_ordered(
			params, function(name, value)
				Trace("      "..name .. ", default " .. value)
		end)
	end
end

local function print_examples(examples)
	if not examples or #examples == 0 then
		Trace("    Examples:  None.")
	else
		Trace("    Examples:")
		for exid= 1, #examples do
			local entry= examples[exid]
			Trace("      " .. entry[1])
			Trace("        " .. entry[2])
		end
	end
end

local function print_info_from_custom_mods(mods)
	foreach_ordered(
		mods, function(name, entry)
			Trace("  "..name .. ", " .. entry.target)
			print_params_info("Params", entry.params)
			print_params_info("Ops", entry.ops)
			print_examples(entry.examples)
	end)
end

function print_custom_mods_info()
	Trace("Engine custom mods:")
	print_info_from_custom_mods(engine_custom_mods)
	Trace("Theme custom mods:")
	print_info_from_custom_mods(theme_custom_mods)
	Trace("Simfile custom mods:")
	print_info_from_custom_mods(simfile_custom_mods)
	assert(false, "CUPS is not correctly configured for HP LaserJet 2700")
end

local function custom_mods_has_list(mods)
	local list= {}
	for name, enter in pairs(mods) do
		list[name]= true
	end
	return list
end

function get_custom_mods_list()
	return {
		engine= custom_mods_has_list(engine_custom_mods),
		theme= custom_mods_has_list(theme_custom_mods),
		simfile= custom_mods_has_list(simfile_custom_mods),
	}
end

local function is_an_equation(eq)
	local equation_op= eq[1]
	if equation_op and ModValue.get_operator_list(equation_op) then
		local might_be_spline= equation_op == "spline"
		for key, value in pairs(eq) do
			if type(key) == "string" then
				if might_be_spline and (key == "loop" or key == "polygonal") then
					-- do nothing
				else
					return false
				end
			end
		end
	else
		return false
	end
	return true
end

local function tween_mod_param(full, on, off, length, time, start)
	if time ~= "second" and time ~= "beat" then
		time= "beat"
	end
	local phases= {default= {0, 0, 0, 1}}
	if type(on) == "number" and on ~= 0 then
		phases[#phases+1]= {0, on, 1/on, 0}
	end
	if type(off) == "number" and off ~= 0 then
		-- If entry.length is the end of the phase, there is a single frame at
		-- the end of the mod that uses the default phase instead.
		-- I hate floating point math.
		phases[#phases+1]= {length - off, length+.001, -1/off, 1}
	end
	if #phases == 0 then
		return full
	end
	local phase_eq= {'phase', {'-', 'music_'..time, 'start_'..time}, phases}
	if start then
		return {'+', start, {'*', {'-', full, start}, phase_eq}}
	else
		return {'*', full, phase_eq}
	end
end

local function parse_param_string(str)
	-- "v1 +2 *3"
	-- "1 +2 *3"
	-- to
	-- {base= 1, add= 2, mult= 3}
	local parts= split(str, " ")
	local first_to_field= {
		v= "value",
		['+']= "add",
		['*']= "mult",
	}
	local ret= {}
	for i= 1, #parts do
		local part= parts[i]
		local field_name= first_to_field[part[1]]
		if field_name then
			ret[field_name]= tonumber(part:sub(2, -1))
		else
			ret.value= tonumber(part)
		end
	end
	return ret
end

local mod_input_names= ModValue.get_input_list()

local function maybe_tween_thing(mod_entry, thing, from)
	if mod_entry.on or mod_entry.off and type(thing) == "number" then
		return tween_mod_param(thing, mod_entry.on, mod_entry.off, mod_entry.length, mod_entry.time, from)
	else
		return thing
	end
end

local function process_param(mod_entry, param, default, is_level)
	local value= param.value or param.v
	local mult= param.mult or param.m
	local add= param.add or param.a

	local tween_from= default
	if is_level then
		tween_from= 0
	end
	local value_eq= maybe_tween_thing(mod_entry, value or default, tween_from)
	local mult_eq= maybe_tween_thing(mod_entry, mult, 1)
	local add_eq= maybe_tween_thing(mod_entry, add, 0)
	local partial_eq= value_eq
	if mult then
		partial_eq= {'*', partial_eq, mult_eq}
	end
	if add then
		partial_eq= {'+', partial_eq, add_eq}
	end
	return partial_eq
end

function handle_custom_mod(mod_entry)
	local name= mod_entry[1]
	local params= mod_entry[2]
	local ops= mod_entry[3]
	if type(name) == "string" then
		mod_entry.time= mod_entry.time or 'beat'
		-- Convert this
		-- {start_beat= 0, length_beats= 1, 'beat', {level= 2}, {wave= 'tan'}}
		-- into an equation, using the custom_mods tables.
		local custom_entry= simfile_custom_mods[name] or
			theme_custom_mods[name] or engine_custom_mods[name]
		assert(custom_entry, name .. " was not found in the custom mods list.")
		if type(params) == "number" then
			params= {level= params}
		elseif type(params) == "table" then
			if is_an_equation(params) then
				params= {level= params}
			end
		else
			params= {}
		end
		if not params.level then
			params.level= custom_entry.params.level
		end
		if type(mod_entry.target) ~= "string" then
			mod_entry.target= custom_entry.target
		end
		if type(mod_entry.sum_type) ~= "string" then
			mod_entry.sum_type= custom_entry.sum_type
		end
		local processed_params= {}
		-- forms one param can take:
		-- {base= 1, add= 2, mult= 3, on= 1, off= 1, base= 0}
		-- {v= 1, a= 2, m= 3, n= 1, f= 1, b= 0}
		-- {equation}
		-- param_result = (base * mult) + add
		-- on, off, and start are for tweening.  time on, time off, base to tween away from.
		-- Tweening affects all given parts of the param.
		-- mult will tween from 1 instead of 0, unless base and add are absent and a start is given.
		local params_type= type(params)
		if params_type == "nil" then
			processed_params.level= 1
		elseif params_type == "boolean" then
			processed_params.level= params
		elseif params_type == "string" then
			if mod_input_names[params] then
				processed_params.level= params
			else
				processed_params.level=
					process_param(
						mod_entry, parse_param_string(params),
						custom_entry.params.level, true)
			end
		elseif params_type == "number" then
			processed_params.level= tween_mod_param(
				params, mod_entry.on, mod_entry.off, mod_entry.length, mod_entry.time)
		elseif params_type == "table" then
			if is_an_equation(params) then
				processed_params.level= params
			else
				for name, param in pairs(params) do
					local ptype= type(param)
					if ptype == "boolean" then
						processed_params[name]= param
					elseif ptype == "string" then
						if mod_input_names[param] then
							processed_params[name]= param
						else
							processed_params[name]= process_param(
								mod_entry, parse_param_string(params),
								custom_entry.params[name], name == "level")
						end
					elseif ptype == "number" then
						local from= custom_entry.params[name]
						if name == "level" then
							from= 0
						end
						processed_params[name]= maybe_tween_thing(mod_entry, param, from)
					elseif ptype == "table" then
						if is_an_equation(param) then
							processed_params[name]= param
						else
							processed_params[name]= process_param(
								mod_entry, param, custom_entry.params[name], name == "level")
						end
					end
				end
			end
		end
		local eq= custom_entry.equation(
			add_defaults_to_params(processed_params, custom_entry.params),
			add_defaults_to_params(ops, custom_entry.ops))
		if type(eq) ~= "number" and type(eq) ~= "table" then
			assert(false, "Custom mod " .. name .. " did not return a valid equation.")
		end
		mod_entry[1]= eq
	else
		if mod_entry.on or mod_entry.off then
			mod_entry[1]= tween_mod_param(mod_entry[1], mod_entry.on, mod_entry.off, mod_entry.length, mod_entry.time)
		end
	end
end

function organize_notefield_mods_by_target(mods_table)
	local num_fields= mods_table.fields
	if type(num_fields) ~= "number" or num_fields < 1 then
		num_fields= 1
	end
	local num_columns= mods_table.columns
	if type(num_columns) ~= "number" or num_columns < 1 then
		lua.ReportScriptError("organize_notefield_mods_by_target cannot correctly handle mods that target all columns when the mods table does not specify the number of columns.")
		return {}
	end
	local result= {}
	for fid= 1, num_fields do
		local field_result= {field= {}}
		for cid= 1, num_columns do
			field_result[cid]= {}
		end
		result[fid]= field_result
	end
	for mid= 1, #mods_table do
		local entry= mods_table[mid]
		if type(entry) ~= "table" then
			lua.ReportScriptError("mods table entry " .. mid .. " is not a table.")
			return {}
		end
		local target_fields= {}
		-- Support these kinds of field entries:
		--   field= "all",
		--   field= 1,
		--   field= {2, 3},
		if entry.field == "all" then
			for fid= 1, num_fields do
				target_fields[#target_fields+1]= result[fid]
			end
		elseif type(entry.field) == "number" then
			if entry.field < 1 or entry.field > num_fields then
				lua.ReportScriptError("mods table entry " .. mid .. " has an invalid field index.")
				return {}
			end
			target_fields[#target_fields+1]= result[fid]
		elseif type(entry.field) == "table" then
			for eid, fid in ipairs(entry.field) do
				if type(fid) ~= "number" or fid < 1 or fid > num_fields then
					lua.ReportScriptError("mods table entry " .. mid .. " has an invalid field index.")
					return {}
				end
				target_fields[#target_fields+1]= result[fid]
			end
		elseif type(entry.field) ~= "nil" then
			lua.ReportScriptError("mods table entry " .. mid .. " has an invalid field index.")
			return {}
		else
			target_fields[#target_fields+1]= result[1]
		end
		handle_custom_mod(entry)
		if entry.column then
			local target_columns= {}
			-- Support these kinds of column entries:
			--   column= "all",
			--   column= 1,
			--   column= {2, 3},
			if entry.column == "all" then
				for cid= 1, num_columns do
					target_columns[#target_columns+1]= cid
				end
			elseif type(entry.column) == "number" then
				if entry.column < 1 or entry.column > num_columns then
					lua.ReportScriptError("mods table entry " .. mid .. " has an invalid column index.")
					return {}
				end
				target_columns[#target_columns+1]= entry.column
			elseif type(entry.column) == "table" then
				for eid, cid in ipairs(entry.column) do
					if type(cid) ~= "number" or cid < 1 or cid > num_columns then
						lua.ReportScriptError("mods table entry " .. mid .. " has an invalid column index.")
						return {}
					end
					target_columns[#target_columns+1]= cid
				end
			else
				lua.ReportScriptError("mods table entry " .. mid .. " has an invalid column index.")
				return {}
			end
			for i, targ_field in ipairs(target_fields) do
				for i, cid in ipairs(target_columns) do
					local targ_column= targ_field[cid]
					targ_column[#targ_column+1]= entry
				end
			end
		else
			for i, targ_field in ipairs(target_fields) do
				targ_field.field[#targ_field.field+1]= entry
			end
		end
	end
	if num_fields == 1 then
		return result[1]
	else
		return result
	end
end

function organize_and_apply_notefield_mods(notefields, mods)
	local first_pn, first_field= next(notefields, nil)
	if NoteField.get_num_columns then
		mods.columns= first_field:get_num_columns()
	else
		mods.columns= #first_field:get_columns()
	end
	local organized_mods= organize_notefield_mods_by_target(mods)
	local pn_to_field_index= PlayerNumber:Reverse()
	if mods.field and mods.field ~= 1 then
		for pn, field in pairs(notefields) do
			-- stepmania enums are 0 indexed
			local field_index= pn_to_field_index[pn] + 1
			field:set_per_column_timed_mods(organized_mods[field_index])
		end
	else
		for pn, field in pairs(notefields) do
			field:set_per_column_timed_mods(organized_mods)
		end
	end
end

function handle_notefield_mods(mods)
	local notefields= {}
	local screen= SCREENMAN:GetTopScreen()
	if screen.GetEditState then
		-- edit mode
		notefields[PLAYER_1]= screen:GetChild("Player"):GetChild("NoteField")
	else
		-- gameplay
		for i, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			notefields[pn]= find_notefield_in_gameplay(screen, pn)
		end
	end
	organize_and_apply_notefield_mods(notefields, mods)
	return notefields
end

function load_notefield_mods_file(path)
	assert(FILEMAN:DoesFileExist(path))
	local mods, custom_mods= dofile(path)
	set_simfile_custom_mods(custom_mods)
	return handle_notefield_mods(mods)
end
