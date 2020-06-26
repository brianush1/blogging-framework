@echo off
if not exist site (
	mkdir site
)
lua build/init.lua
