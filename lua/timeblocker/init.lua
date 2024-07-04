local M = {}
local cut_content = nil
local namespace_id = nil
local header_1 = "+:add  -:remove  .:repeat   r:reset"
local header_2 = "c:copy x:cut     v:paste_block"

local default_options = {
	start_hour = 7,
	end_hour = 17,
	now_color = "#ff007c",
}

local function setup_highlight(color)
	vim.cmd("highlight NowHighlight guifg=" .. color .. " gui=bold ctermfg=198 cterm=bold ctermbg=black")
end

local function get_previous_half_hour()
	local current_time = os.date("*t")
	local minute = current_time.min < 30 and 0 or 30
	local hour = current_time.hour
	local period = hour >= 12 and "PM" or "AM"

	if hour > 12 then
		hour = hour - 12
	elseif hour == 0 then
		hour = 12
	end

	return string.format("%02d:%02d %s", hour, minute, period)
end

local function find_matching_time_label(previous_half_hour)
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	for i, line in ipairs(lines) do
		local time_label = string.match(line, "(%d%d:%d%d %a%a)")
		if time_label == previous_half_hour then
			return i - 1 -- Return the line number (0-based)
		end
	end

	return nil -- Return nil if no match is found
end

-- Function to get the file path based on today's date
local function get_file_path()
	return vim.fn.expand("~/time-blocker/blocked-day.txt") -- Change to your desired directory
end

-- Function to read file content into a table of lines
local function read_file(file_path)
	local lines = {}
	local file = io.open(file_path, "r")
	if file then
		for line in file:lines() do
			table.insert(lines, line)
		end
		file:close()
	end
	return lines
end

-- Function to write default content to a new file
local function write_default_content(file_path)
	local file = io.open(file_path, "w")
	if file then
		file:write(header_1 .. "\n")
		file:write(header_2 .. "\n\n")
		for hour = M.options.start_hour, M.options.end_hour - 1 do
			file:write("------------------\n")
			file:write(string.format("%02d:00 %s\n", (hour - 1) % 12 + 1, hour < 12 and "AM" or "PM"))
			file:write("------------------\n")
			file:write(string.format("%02d:30 %s\n", (hour - 1) % 12 + 1, hour < 12 and "AM" or "PM"))
		end
		file:close()

		local buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_add_highlight(buf, -1, "MyCustomHighlight", 0, 0, -1) -- Highlight the first line
		vim.api.nvim_buf_add_highlight(buf, -1, "MyCustomHighlight", 2, 0, -1) -- Highlight the third line
	end
end

local function update_now_highlight()
	local previous_half_hour = get_previous_half_hour()
	local matching_line = find_matching_time_label(previous_half_hour)

	if matching_line and namespace_id then
		local buf = vim.api.nvim_get_current_buf()
		-- Remove any existing highlights in the namespace
		vim.api.nvim_buf_clear_namespace(buf, namespace_id, 0, -1)
		-- Add the highlight to the matching line
		vim.api.nvim_buf_add_highlight(buf, namespace_id, "NowHighlight", matching_line, 0, -1)
	end
end

function M.open_timeblocker()
	setup_highlight(M.options.now_color)
	-- Get the file path based on today's date
	local file_path = get_file_path()
	namespace_id = vim.api.nvim_create_namespace("TimeBlockNamespace")

	-- Create a new buffer and set it as the current buffer
	vim.cmd("enew")
	local buf = vim.api.nvim_get_current_buf()

	-- Check if the file exists
	local lines
	if vim.fn.filereadable(file_path) == 1 then
		-- Load the file content
		lines = read_file(file_path)
	else
		-- Create the file with default content
		write_default_content(file_path)
		lines = read_file(file_path)
	end

	-- Set the buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Optionally, set some buffer options (e.g., make it non-modifiable)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	-- Set key mappings
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"+",
		':lua require("timeblocker").add_new_block()<CR>',
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"-",
		':lua require("timeblocker").remove_block()<CR>',
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		".",
		':lua require("timeblocker").repeat_block()<CR>',
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"c",
		':lua require("timeblocker").copy_block()<CR>',
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"x",
		':lua require("timeblocker").cut_block()<CR>',
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"v",
		':lua require("timeblocker").paste()<CR>',
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"r",
		':lua require("timeblocker").reset()<CR>',
		{ noremap = true, silent = true }
	)

	-- Create a timer
	local timer = vim.loop.new_timer()

	-- Start the timer to call update_buffer every 30 seconds (30000 milliseconds)
	timer:start(0, 30000, vim.schedule_wrap(update_now_highlight))

	-- Ensure the timer is stopped when NeoVim exits
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			timer:stop()
			timer:close()
		end,
	})
end

function M.add_new_block()
	-- Get the current line number and line content
	local buf = vim.api.nvim_get_current_buf()
	local line_nr = vim.fn.line(".") - 1
	local line_content = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]

	-- Check if the line is a time block
	if string.match(line_content, "%d%d:%d%d %a%a") then
		-- Extract the time portion of the line
		local time = string.match(line_content, "(%d%d:%d%d %a%a)")

		-- Get the block name
		local block_name = vim.fn.input("Enter block name: ")

		-- Update the line with the block name, preserving the time
		local updated_line = string.format("%s    %s", time, block_name)

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { updated_line })
		vim.bo[buf].modifiable = false

		-- Save the updated buffer content back to the file
		local file_path = get_file_path()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local file = io.open(file_path, "w")
		if file then
			for _, line in ipairs(lines) do
				file:write(line .. "\n")
			end
			file:close()
		end
		update_now_highlight()
	end
end

function M.remove_block()
	-- Get the current line number and line content
	local buf = vim.api.nvim_get_current_buf()
	local line_nr = vim.fn.line(".") - 1
	local line_content = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]

	-- Check if the line is a time block
	if string.match(line_content, "%d%d:%d%d %a%a") then
		-- Extract the time portion of the line
		local time = string.match(line_content, "(%d%d:%d%d %a%a)")

		-- Update the line, preserving only the time
		local updated_line = string.format("%s", time)

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { updated_line })
		vim.bo[buf].modifiable = false

		-- Save the updated buffer content back to the file
		local file_path = get_file_path()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local file = io.open(file_path, "w")
		if file then
			for _, line in ipairs(lines) do
				file:write(line .. "\n")
			end
			file:close()
		end
		update_now_highlight()
	end
end

function M.repeat_block()
	-- Get the current line number and line content
	local buf = vim.api.nvim_get_current_buf()
	local line_nr = vim.fn.line(".") - 1
	local line_content = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]

	-- Check if the line is a time block
	if string.match(line_content, "%d%d:%d%d %a%a") then
		-- Extract the time portion of the line
		local time = string.match(line_content, "(%d%d:%d%d %a%a)")

		-- Find the previous block with a label
		local prev_line_nr = line_nr - 1
		local prev_label
		while prev_line_nr >= 0 do
			local prev_line_content = vim.api.nvim_buf_get_lines(buf, prev_line_nr, prev_line_nr + 1, false)[1]
			if string.match(prev_line_content, "%d%d:%d%d %a%a (.+)") then
				prev_label = string.match(prev_line_content, "%d%d:%d%d %a%a (.+)")
				break
			end
			prev_line_nr = prev_line_nr - 1
		end

		if prev_label then
			-- Update the line with the previous block label, preserving the time
			local updated_line = string.format("%s %s", time, prev_label)

			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { updated_line })
			vim.bo[buf].modifiable = false

			-- Save the updated buffer content back to the file
			local file_path = get_file_path()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local file = io.open(file_path, "w")
			if file then
				for _, line in ipairs(lines) do
					file:write(line .. "\n")
				end
				file:close()
			end

			local next_line_nr = line_nr + 2
			vim.api.nvim_win_set_cursor(0, { next_line_nr + 1, 0 })
		end
		update_now_highlight()
	end
end

function M.paste_block()
	-- Get the current line number
	local buf = vim.api.nvim_get_current_buf()
	local line_nr = vim.fn.line(".") - 1

	-- Check if there is cut_content to paste
	if cut_content then
		-- Get the current line content
		local current_line = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]

		-- Check if the current line has a time format (e.g., "09:00am")
		local current_time = string.match(current_line, "%d%d:%d%d %a%a")
		if current_time then
			-- Combine the stored label with the current time
			local updated_line = string.format("%s %s", current_time, cut_content)

			-- Ensure buffer modifiability is enabled
			vim.bo[buf].modifiable = true

			-- Set the updated line
			vim.api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { updated_line })

			-- Disable buffer modifiability after modification
			vim.bo[buf].modifiable = false

			-- Save the updated buffer content back to the file
			local file_path = get_file_path()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local file = io.open(file_path, "w")
			if file then
				for _, line in ipairs(lines) do
					file:write(line .. "\n")
				end
				file:close()
			end
		end
		update_now_highlight()
	end
end

function M.copy_block()
	-- Get the current line number and line content
	local buf = vim.api.nvim_get_current_buf()
	local line_nr = vim.fn.line(".") - 1
	local line_content = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]

	-- Check if the line is a time block
	if string.match(line_content, "%d%d:%d%d %a%a") then
		-- Extract the label portion of the line (if any)
		local label = string.match(line_content, "%d%d:%d%d %a%a%s+(.+)")

		-- Update the cut_content to copy
		cut_content = label or ""
	end
end

function M.cut_block()
	-- Get the current line number and line content
	local buf = vim.api.nvim_get_current_buf()
	local line_nr = vim.fn.line(".") - 1
	local line_content = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]

	-- Check if the line is a time block
	if string.match(line_content, "%d%d:%d%d %a%a") then
		-- Extract the time portion of the line
		local time = string.match(line_content, "(%d%d:%d%d %a%a)")

		-- Extract the label portion of the line (if any)
		local label = string.match(line_content, "%d%d:%d%d %a%a%s+(.+)")

		-- Update the cut_content to cut
		cut_content = label or ""

		-- Update the line, preserving only the time
		local updated_line = string.format("%s", time)

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { updated_line })
		vim.bo[buf].modifiable = false

		-- Save the updated buffer content back to the file
		local file_path = get_file_path()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local file = io.open(file_path, "w")
		if file then
			for _, line in ipairs(lines) do
				file:write(line .. "\n")
			end
			file:close()
		end
	end
end

function M.reset()
	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].modifiable = true

	-- Clear the buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

	-- Optionally, write default content to the file
	local file_path = get_file_path()
	write_default_content(file_path)

	-- Read the default content and set it in the buffer
	local lines = read_file(file_path)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Ensure buffer options are set appropriately
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	update_now_highlight()
end

function M.setup(user_options)
	print("Inside setup function")
	M.options = vim.tbl_deep_extend("force", default_options, user_options)
	vim.api.nvim_create_user_command("TimeBlocker", function()
		require("timeblocker").open_timeblocker()
	end, {})
end

return M
