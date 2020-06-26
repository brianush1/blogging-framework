local Lexer = {}

local function isWhitespace(c)
	return (" \t\r\n"):find(c, 1, true)
end

local function isDigit(c)
	return ("0123456789"):find(c, 1, true)
end

local function isAlpha(c)
	return ("qwertyuiopasdfghjklzxcvbnm_"):find(c:lower(), 1, true)
end

local function isAlphanumeric(c)
	return isAlpha(c) or isDigit(c)
end

local symbols = {
	"+", "-", "*", "/", "%", "^", "#",
	"==", "~=", "<=", ">=", "<", ">", "=",
	"(", ")", "{", "}", "[", "]",
	";", ":", ",", ".", "..", "...",
}

-- sort symbols in decreasing length in order to perform maximal munch
table.sort(symbols, function(a, b)
	return #a > #b
end)

local keywords = {
	"and",
	"break",
	"do",
	"else",
	"elseif",
	"end",
	"false",
	"for",
	"function",
	"if",
	"in",
	"local",
	"nil",
	"not",
	"or",
	"repeat",
	"return",
	"then",
	"true",
	"until",
	"while",
}

for _, v in ipairs(keywords) do
	keywords[v] = true
end

local function isKeyword(word)
	return not not keywords[word]
end

local tokenMetatable = {
	__tostring = function(self)
		return self.kind .. " '" .. self.value .. "'"
	end,
}

function Lexer.new(document, source, problems)
	local self = setmetatable({}, Lexer)

	self.document = document
	self.source = source
	self._position = {
		line = 1,
		column = 1,
		index = 1,
	}
	self.problems = problems
	self.peekedToken = nil

	return self
end

function Lexer:__index(key)
	if key == "position" then
		return {
			line = self._position.line,
			column = self._position.column,
			index = self._position.index,
		}
	else
		return Lexer[key]
	end
end

function Lexer:range(from, to)
	if not to then
		to = self.position
	end
	return {
		from = from,
		to = to,
		document = self.document
	}
end

function Lexer:peekChar(skip)
	local i = self._position.index + (skip or 0)
	return self.source:sub(i, i)
end

function Lexer:peekSegment(length)
	local i = self._position.index
	local res = self.source:sub(i, i + length - 1)
	if #res == length then
		return res
	else
		return ""
	end
end

function Lexer:nextChar()
	local res = self:peekChar()
	if res ~= "" then
		self._position.index = self._position.index + 1
		if res == "\n" then
			self._position.line = self._position.line + 1
			self._position.column = 1
		else
			self._position.column = self._position.column + 1
		end
	end
	return res
end

function Lexer:nextSegment(length)
	local value = {}
	for i = 1, length do
		local c = self:nextChar()
		if c == "" then
			return ""
		end
		table.insert(value, c)
	end
	return table.concat(value)
end

function Lexer:eofChar()
	return self:peekChar() == ""
end

function Lexer:readWhile(predicate)
	local result = {}
	while not self:eofChar() and predicate(self:peekChar()) do
		table.insert(result, self:nextChar())
	end
	return table.concat(result)
end

function Lexer:skipWhitespace()
	self:readWhile(isWhitespace)
end

function Lexer:readLongString()
	if self:peekChar() ~= "[" then
		return nil
	end

	local level = 1
	-- [[ is level 1
	-- [=[ is level 2
	-- [==[ is level 3

	while self:peekChar(level) == "=" do
		level = level + 1
	end

	local from, to

	if self:peekChar(level) == "[" then
		from = self.position
		self:nextSegment(level + 1) -- skip over opening part
		to = self.position
	else
		return nil
	end

	local complement = "]" .. ("="):rep(level - 1) .. "]"

	local value = {}

	while self:peekSegment(#complement) ~= complement and not self:eofChar() do
		table.insert(value, self:nextChar())
	end

	if self:eofChar() then
		table.insert(self.problems, {
			kind = "error",
			ranges = { self:range(from, to) },
			message = "unclosed string literal",
		})
	else -- if it's not eof, the loop stopped because it found the closing sequence
		self:nextSegment(#complement)
	end

	if value[1] == "\n" then
		return table.concat(value, "", 2)
	elseif value[1] == "\r" and value[2] == "\n" then
		return table.concat(value, "", 3)
	else
		return table.concat(value)
	end
end

function Lexer:nextInternal()
	self:skipWhitespace()

	if self:peekSegment(2) == "--" then
		local longComment = self:readLongString()
		if not longComment then
			self:readWhile(function(c)
				return c ~= "\n"
			end)
		end

		return self:nextInternal()
	end

	local from = self.position
	local c = self:peekChar()

	if c == "" then
		return {
			kind = "eof",
			range = self:range(from),
		}
	end

	local longStringValue = self:readLongString()
	if longStringValue then
		return {
			kind = "string",
			value = longStringValue,
			range = self:range(from),
		}
	end

	if isDigit(c) or (c == "." and isDigit(self:peekChar(1))) then
		local dot = false
		local value = self:readWhile(function(c)
			if isDigit(c) then
				return true
			elseif c == "." and not dot then
				dot = true
				return true
			else
				return false
			end
		end)

		if self:peekChar():lower() == "e" then
			self:nextChar()
			value = value .. "e"
			local sign = self:peekChar()
			if sign == "+" or sign == "-" then
				self:nextChar()
				value = value .. sign
			end
			value = value .. self:readWhile(isDigit)
		end

		value = tonumber(value)
		if value == nil then
			error("Internal compiler error")
		end

		return {
			kind = "number",
			value = value,
			range = self:range(from)
		}
	end

	if c == "\"" or c == "'" then
		self:nextChar()
		local to = self.position
		local value = {}
		local escape = false
		while not self:eofChar() do
			local ch = self:peekChar()

			if escape then
				escape = false
				if ch == "a" then ch = "\a" end
				if ch == "b" then ch = "\b" end
				if ch == "f" then ch = "\f" end
				if ch == "n" then ch = "\n" end
				if ch == "r" then ch = "\r" end
				if ch == "t" then ch = "\t" end
				if ch == "v" then ch = "\v" end
				if ch == "\r" then
					self:nextChar()
					if self:peekChar() == "\n" then
						self:nextChar()
					end
					table.insert(value, "\n")
				elseif ch == "\n" then
					self:nextChar()
					table.insert(value, "\n")
				elseif isDigit(ch) then
					local num = 0
					for i = 1, 3 do
						local digit = self:peekChar()
						if isDigit(digit) then
							self:nextChar()
							num = num * 10
							num = num + (digit:byte() - 48)
						else
							break
						end
					end
					table.insert(value, string.char(num))
				else
					self:nextChar()
					table.insert(value, ch)
				end
			elseif ch == "\\" then
				self:nextChar()
				escape = true
			elseif ch == c or ch == "\r" or ch == "\n" then
				break
			else
				table.insert(value, self:nextChar())
			end
		end
		if self:nextChar() ~= c then
			table.insert(self.problems, {
				kind = "error",
				ranges = { self:range(from, to) },
				message = "unclosed string literal",
			})
		end
		return {
			kind = "string",
			value = table.concat(value),
			range = self:range(from),
		}
	end

	if isAlphanumeric(c) then
		local value = self:readWhile(isAlphanumeric)
		return {
			kind = isKeyword(value) and "keyword" or "name",
			value = value,
			range = self:range(from),
		}
	end

	for _, symbol in ipairs(symbols) do
		if self:peekSegment(#symbol) == symbol then
			local value = self:nextSegment(#symbol)
			return {
				kind = "symbol",
				value = value,
				range = self:range(from),
			}
		end
	end

	local value = self:nextChar()
	return {
		kind = "symbol",
		unintended = true,
		value = value,
		range = self:range(from),
	}
end

function Lexer:next()
	if self.peekedToken then
		local result = self.peekedToken
		self.peekedToken = nil
		return result
	else
		return setmetatable(self:nextInternal(), tokenMetatable)
	end
end

function Lexer:peek()
	self.peekedToken = self:next()
	return self.peekedToken
end

function Lexer:eof()
	return self:isNext("eof")
end

function Lexer:isNext(kind, value)
	local token = self:peek()
	return token.kind == kind and (value == nil or token.value == value)
end

function Lexer:tryConsume(kind, value)
	if self:isNext(kind, value) then
		self:next()
		return true
	else
		return false
	end
end

function Lexer:expectAndRecover(kind, value, mistakes)
	if not self:expect(kind, value) then
		for _, v in ipairs(mistakes) do
			if v == self:peek().value then
				self:next()
				return
			end
		end
	end
end

function Lexer:expect(kind, value, default)
	if self:isNext(kind, value) then
		return self:next()
	else
		local expected
		if value then
			expected = "'" .. value .. "'"
		else
			expected = "<" .. kind .. ">"
		end
		local got
		if self:peek().kind == kind then
			got = "'" .. self:peek().value .. "'"
		else
			got = "<" .. self:peek().kind .. ">"
		end
		table.insert(self.problems, {
			kind = "error",
			ranges = { self:peek().range },
			message = "expected " .. expected .. ", got " .. got,
		})
		if default == nil then
			return nil
		else
			return setmetatable({
				kind = kind,
				value = default,
				range = self:peek().range,
			}, tokenMetatable)
		end
	end
end

local function highlight(code)
	local res = {}
	local lexer = Lexer.new("", code, {})
	local prev = 0
	while not lexer:eof() do
		local token = lexer:next()
		local range = token.range
		table.insert(res, {"span", code:sub(prev, range.from.index - 1)})
		table.insert(res, {"span", class = token.kind, code:sub(range.from.index, range.to.index - 1)})
		prev = range.to.index
	end
	table.insert(res, {"span", code:sub(prev, #code)})
	return {"fragment", res}
end

return highlight