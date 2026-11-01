local get_targets = ya.sync(function()
	local selected = cx.active.selected

	if #selected > 0 then
		local files = {}

		for _, file in pairs(selected) do
			files[#files + 1] = tostring(file.url)
		end

		return files
	end

	local hovered = cx.active.current.hovered

	if hovered then
		return { tostring(hovered.url) }
	end

	return {}
end)

local function media_menu()
	local choice = ya.which {
		cands = {
			{ on = "i", desc = "Show media information" },
			{ on = "h", desc = "Convert video to H.265" },
			{ on = "a", desc = "Extract audio" },
			{ on = "t", desc = "Test selected files" },
		},
		silent = false,
	}

	if not choice then
		return
	end

	if choice == 1 then
		ya.emit("shell", {
			"ffprobe %h 2>&1 | less -R",
			block = true,
		})
	elseif choice == 2 then
		ya.notify {
			title = "Media",
			content = "Convert to H.265",
			timeout = 3,
			level = "info",
		}
	elseif choice == 3 then
		ya.notify {
			title = "Media",
			content = "Extract audio",
			timeout = 3,
			level = "info",
		}
	elseif choice == 4 then
		local targets = get_targets()

		ya.notify {
			title = "Selected files",
			content = "Anzahl: " .. #targets,
			timeout = 3,
			level = "info",
		}
	end
end

return {
	entry = function(self, job)
		local choice = ya.which {
			cands = {
				{ on = "f", desc = "Files" },
				{ on = "m", desc = "Media" },
				{ on = "s", desc = "Security" },
			},
			silent = false,
		}

		if not choice then
			return
		end

		if choice == 2 then
			media_menu()
		end
	end,
}
