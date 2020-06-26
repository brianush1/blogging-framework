local index = require("posts.index")
local blog = require("posts.blog")
local render = require("build.render")

local indexTable = {}
for i, v in ipairs(index) do
	indexTable[v.file] = i
end

local function page(content, title)
	title = title and blog.title .. " | " .. title or blog.title
	return [[
		<!DOCTYPE html>
		<html>
			<head>
				<meta charset="utf-8">
				<title>]] .. title .. [[</title>
				<link rel="stylesheet" href="style.css">
			</head>
			<body>]] .. content .. [[</body>
		</html>
	]]
end

local function getContents(path)
	if path == "/" then
		local links = {}
		for i = #index, 1, -1 do
			local v = index[i]
			table.insert(links, ([[<p><a href="%s.html">%s — %s</a></p>]]):format(v.file, v.date, v.title))
		end
		return ([[
			<h1>%s</h1>
			<h2>%s</h2>
			<hr>
			%s
		]]):format(
			blog.title,
			blog.description or "",
			table.concat(links)
		)
	else
		local data = index[indexTable[path:sub(2)]]
		local other = {}
		for i = #index, 1, -1 do
			local v = index[i]
			table.insert(other, ([[<p><a href="%s.html">%s</a></p>]]):format(v.file, v.title))
		end
		return ([[%s<div class="other-pages"><h4>Other posts</h4>%s</div>]]):format(render(data), table.concat(other))
	end
end

local function serve(path)
	return page(getContents(path))
end

local function writeToFile(file, content)
	local f = io.open("site/" .. file, "w")
	f:write(content)
	f:close()
end

local style = io.open("build/style.css", "r")
writeToFile("style.css", style:read("*a"))
style:close()

writeToFile("index.html", serve("/"))
for _, v in ipairs(index) do
	writeToFile(v.file .. ".html", serve("/" .. v.file))
end