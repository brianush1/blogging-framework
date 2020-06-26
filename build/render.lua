local function render(data)
	local doc = require("build.mu").new()
	require("posts." .. data.file)(doc)
	return ([[<h1>%s</h1><h2>%s</h2><hr>%s]]):format(
		data.title, data.caption or "",
		doc:html())
end

return render