return function(doc)
	doc:p [[
		Hello there! This is an example article to get you started.
		You can make footnotes^ and code:
	]]

	doc:fn "Footnotes!"

	doc:code("lua", [[
		local msg = "This is some neat code"
		if 2 < 3 then
			print(msg)
		end
	]])

	doc:h "More examples"

	doc:p "Inline " {"b", "bold"} ", " {"i", "italics"} ", and " {"a", href = "https://example.org/", "linked"} " text is supported"

	doc:p "Complex footnotes!^"

	doc:fn(function()
		doc:p [[
			Here's a footnote with multiple paragraphs, code, and horizontal lines.
		]]

		doc:code("lua", [[
			print("my code")
		]])

		doc:hr()

		doc:p [[
			Add as many elements as you like.
		]]
	end)

	doc:p [[
		2 ^^ 3 = 8
	]]

	doc:ul {
		"a",
		"b",
		"This is a list",
		function()
			doc:p [[With complex items!!]]

			doc:hr()

			doc:code("lua", [[
				print("my code")
			]])
		end,
	}
end