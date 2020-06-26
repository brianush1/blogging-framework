-- programmatic MarkUp language

local unpack = _G.unpack or table.unpack

local Mu = {}
Mu.__index = Mu

function Mu.new()
	local self = setmetatable({}, Mu)

	self.tree = {}
	self.footnotes = {}
	self.fnRef = 1

	return self
end

local function esc(txt)
	return (tostring(txt)
		:gsub("%&", "&amp;")
		:gsub("%<", "&lt;")
		:gsub("%>", "&gt;")
		:gsub("%\"", "&quot;")
		:gsub("%'", "&#39;"))
end

local function render(tree)
	local res = {}
	for _, v in ipairs(tree) do
		if type(v) == "string" then
			table.insert(res, esc(v))
		elseif v[1] == "fragment" then
			table.insert(res, render(v[2]))
		else
			table.insert(res, "<" .. v[1])
			for k, p in pairs(v) do
				if type(k) == "string" then
					table.insert(res, " " .. k .. "=\"" .. esc(p) .. "\"")
				end
			end
			table.insert(res, ">")
			table.insert(res, render({unpack(v, 2)}))
			table.insert(res, "</" .. v[1] .. ">")
		end
	end
	return table.concat(res)
end

function Mu:html()
	if #self.footnotes == 0 then
		return render(self.tree)
	end

	local footnotes = {}

	for i, fn in ipairs(self.footnotes) do
		table.insert(footnotes, {"li",
			id = "fn:" .. i,
			{"fragment", fn},
			" ",
			{"a",
				href = "#fnref:" .. i,
				{"sup", "[return]"}
			},
		})
	end

	return render {
		{"fragment", self.tree},
		{"hr"},
		{"h4", "Footnotes"},
		{"ol", unpack(footnotes)},
	}
end

local function addToPgraph(self, node, content)
	if type(content) == "table" then
		table.insert(node, content)
		return
	end

	local txt = ""
	for i = 1, #content do
		local c = content:sub(i, i)
		if c == "^" and content:sub(i - 1, i) ~= "^^" then
			if content:sub(i, i + 1) ~= "^^" then
				table.insert(node, txt)
				txt = ""
				table.insert(node, {"sup",
					{"a",
						id = "fnref:" .. self.fnRef,
						href = "#fn:" .. self.fnRef,
						"[" .. self.fnRef .. "]",
					},
				})
				self.fnRef = self.fnRef + 1
			end
		else
			txt = txt .. c
		end
	end
	table.insert(node, txt)
end

function Mu:p(content)
	local node = { "p" }
	addToPgraph(self, node, content)
	table.insert(self.tree, node)
	local res
	res = function(extra)
		addToPgraph(self, node, extra)
		return res
	end
	return res
end

local function list(self, items, tag)
	local node = { tag }
	for _, item in ipairs(items) do
		if type(item) == "string" then
			table.insert(node, {"li", item})
		else
			local save = self.tree
			local itemTree = {}
			self.tree = itemTree
			item()
			self.tree = save
			table.insert(node, {"li", {"fragment", itemTree}})
		end
	end
	table.insert(self.tree, node)
end

function Mu:ul(items)
	list(self, items, "ul")
end

function Mu:ol(items)
	list(self, items, "ol")
end

function Mu:fn(func)
	if type(func) == "string" then
		self:fn(function()
			table.insert(self.tree, func)
		end)
		return
	end

	local save = self.tree
	local fnTree = {}
	self.tree = fnTree
	func()
	self.tree = save
	table.insert(self.footnotes, fnTree)
end

function Mu:h(content)
	table.insert(self.tree, {"h4", content})
end

function Mu:code(lang, code, preserveIndent)
	if not preserveIndent then
		local level = math.huge
		local lines = {}
		for line in code:gmatch("[^\r\n]+") do
			table.insert(lines, line)
		end
		local cutoff = 0
		for i, line in ipairs(lines) do
			if i == #lines and line:gsub("\t", "") == "" then
				cutoff = #line + 1
				break
			end

			local num = 0
			while line:sub(num + 1, num + 1) == "\t" do
				num = num + 1
			end
			level = math.min(level, num)
		end
		code = code:sub(level + 1, #code - cutoff):gsub("\n" .. ("\t"):rep(level), "\n")
	end

	local s, highlighter = pcall(require, "build.highlighters." .. lang)
	local contents = code
	if s then
		contents = highlighter(code)
	end
	table.insert(self.tree, {"code", class = "block", contents})
end

function Mu:hr()
	table.insert(self.tree, {"hr"})
end

return Mu