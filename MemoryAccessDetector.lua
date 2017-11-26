require "InstructionDecoder" -- InstDecoder

-- Module Input ------------------------------------------------------------------
-- Base register of block to Log writes/reads of (ex. 0x02000000)
base = 0x02001B80
-- The size of the memory block (ex. 0x22)
size = 0x84
-- In case the block of memory (or struct) has a name. Useful for other programs
name = "s_02001B80"
-- Switches to determine whether to detect on writes, reads, both, ...or neither
detectWrites = true
detectReads = false

-- Optional Setttings ------------------------------------------------------------
--[[ Number of entries in one line. A line is automatically printed when it has
	 that many entries.]]
entriesPerLine = 3
-- Enables detect notification to VBA screen
printToScreen = true
--[[ This is enabled so that meta information about the memblock is displayed at
     start. This could be useful for other software operating on the output of this
	 program. ]] 
metaEnabled = true
--[[ if <lineReleaseTime> frames pass while the line is not empty, 
	 its contents are automatically printed. It may also be set to a relatively
	 high value so that it may only occur in the end. It can be fast forwarded into,
	 as well. Set to -1 to disable automatic line release.]]
lineReleaseTime = -1
--[[ Alternatively, You may want to print the line manually instead of relying on
	 automatic release. This sets the key that activates manual release.
	 To disable this feature, set lineReleaseKey to -1. Default: 'P'.]]
lineReleaseKey = 'P'

-- Globals ----------------------------------------------------------------------
-- Memory accesses detected for write
STR_entries = {}
-- Used to print with no endline. For some reason, I can't do io.write(). 
line = ''
--[[ The timer decrements each frame the line is not empty. If it's added to,
	 or if the line has been printed, it resets.]]
lineReleaseTimer = lineReleaseTime

function main()
	if metaEnabled then
		print(string.format("name=%s, size=0x%X", name, size))
	end

	-- Detection mode on!
	while true do
		releaseLine() -- This is called (if enabled) due to a hack in printing, since i can't print without endline ><
		manualLineRelease() -- This is manual control through resding input
		if detectWrites then
			registerStructWrite(base, size, detectWrite)
		end
		if detectReads then -- TODO: change to detectRead?
			registerStructRead(base, size, detectWrite)
		end
		vba.frameadvance()
	end
end

--[[
 the function func is called whenever a write to the structure at address addr is detected
]]
function registerStructWrite(addr, size, func)
	for i=addr,addr+size do
		memory.registerwrite(i, func)
	end
end

--[[
 the function func is called whenever a read to the structure at address addr is detected
]]
function registerStructRead(addr, size, func)
	for i=addr,addr+size do
		memory.registerread(i, func)
	end
end


--[[
	This assumes that the write to be detected is in THUMB mode.
]]
function detectWrite()
	local pc = memory.getregister("r15") - 4  -- -4 b/c two instruction lag
	local inst = InstDecoder.decode_LdrStr(pc)
	if not inArray(pc, STR_entries) and inst ~= nil then
		table.insert(STR_entries, pc)
		local funcAddr = findFuncAddr(pc)
		local utype = getType(inst)
		local utype_str = (utype ~= -1) and "u"..utype or "?"
		local offset = getOffset(inst)
		local offset_str = (offset ~= -1) and string.format("0x%02X", offset) or "-1"

		local msg = string.format("%s::%08X %s(%s)", funcAddr, pc, utype_str, offset_str)
		if printToScreen then
			vba.message(msg)
		end
		local endline = true
		if #STR_entries % entriesPerLine == 0 then
			printSameLine(msg..", ", endline)
		else
			printSameLine(msg..", ", not endline)
		end
	end
    -- vba.pause()
end


--[[
	Returns the address of the last observed push {r14}. If a pop{pc} was found before that,
	it returns '?' This is only operatable in THUMB.
	@param addr	Address of access. Presumably PC at this point. (or a point just before that...)
	@return address of push {r14} or '?'
]]
function findFuncAddr(addr)
	local curr = addr
	local output = "?"
	local stillSearching = true
	while stillSearching do
		inst = InstDecoder.decode_PushPop(curr)
		if inst ~= nil and inst["R"] == 1 then
			stillSearching = false
			if inst["L"] == 0 then -- yay detected a push {lr} before pop {pc}!
				output = string.format("%08X", curr)
			end
		end
		curr = curr - 2
	end
	return output
end

--[[
	@param inst the STR/LDR decoded instruction table to be extracted from
	@return the size of an STR/LDR instruction. STR/LDR: 32, STRH/LDRH: 16,
	STRB/LDRB = 8.
]]
function getType(inst)
	local output = -1
	if inst["magic"] == IMM or inst["magic"] == REG then
		if inst["B"] == 0 then
			output = 32
		elseif inst["B"] == 1 then
			output = 8
		end
	elseif inst["magic"] == IMM_H or inst["magic"] == REG_H then
		output = 16
	end
	return output
end

--[[
	Gets the offset of an LDR/STR instruction
	@param inst A table representing the decoded instruction
	@return the offset in the intruction if present
]]
function getOffset(inst)
	local output = -1
	if inst["magic"] == IMM then
		if inst["B"] == 0 then
			output = inst["Off7"]
		elseif inst["B"] == 1 then
			output = inst["Off5"]
		end
	elseif inst["magic"] == IMM_H then
		output = inst["Off6"]
	end
	return output
end

--[[
	This is sort of a hack. io.write() is not available, so this is an implementation of it
	with print.
	@param str 		string to add to line (and perhaps print)
	@param newLine	if true, the string is appended and then the line is printed. otherwise,
					the string is only appended to the line
]]
function printSameLine(str, newLine)
	-- the line is emptied or appended to: reset timer
	lineReleaseTimer = lineReleaseTime
	line = line..str
	if newLine then
		print(line)
		line = ''
	end
end

--[[
	This is called every frame, and if the lineReleaseTimer reaches zero, and the line is not empty,
	it is printed. The lineReleaseTimer is reset.
]]
function releaseLine()
	if lineReleaseTime == -1 then
		return
	end
	if lineReleaseTimer ~= 0 then
		lineReleaseTimer = lineReleaseTimer - 1
	elseif lineReleaseTimer == 0 and line ~= '' then
		newLine = true
		printSameLine('', newLine)
	end
end

--[[
	TODO: doc
]]
function manualLineRelease()
	if lineReleaseKey == -1 then
		return
	end
	inputTable = input.get()
	if inputTable[lineReleaseKey] and line ~= '' then
		newLine = true
		printSameLine('', newLine)
	end
end

--[[
 Returns whether the value <value> is in the array <arr>
 @param value	value to check for
 @param arr		array to check for value in
 @return whether the value was in the array
]]
function inArray(value, arr)
	local wasThere = false
	for k,v in ipairs(arr) do
		if v == value then
			wasThere = true
		end
	end
	return wasThere
end

main()
