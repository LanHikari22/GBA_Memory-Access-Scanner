-- Module Input ------------------------------------------------------------------
-- Base register of block to Log writes/reads of (ex. 0x02000000)
base = 0x02005F48
-- The size of the memory block (ex. 0x22)
size = 0x1B0
-- In case the block of memory (or struct) has a name. Useful for other programs
name = "NPC"
-- Switches to determine whether to detect on writes, reads, both, ...or neither
detectWrites = true
detectReads = true

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


-- Constants (wannabe, please don't change :'( )-----------------------------------
-- Magic to identify instructions
IMM = 	  0x6000 -- 0b0110_0000_0000_0000
IMM_H =   0x8000 -- 0b1000_0000_0000_0000
REG = 	  0x5000 -- 0b0101_0000_0000_0000
REG_H =	  0x5200 -- 0b0101_0010_0000_0000
PUSHPOP = 0xB400 -- 0b1011_0100_0000_0000


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
	local inst = decodeLSIntruction(pc)
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
	Decodes an Load/Store instruction and returns a table. Type dependent on op (and magic).
	Only loads/stores of the types "str r0, [r1, r2]" and "ldr r5, [r6, 0xFF]" are decoded.
	op is found in MSB 3 bits or 4 bits. 
	magic will be IMM, IMM_H, REG, or REG_H. Indicating halfword vs not, and immediate offset vs not.
	All keys are strings.
	op = 0b011: {magic, op, B, L, Off7/5, Rb, Rd} (B=byte, L=Load, if B': Off7 will be Off5<<2 from inst)
	op = 0b1000: {magic, op, L, off6, Rb, Rd} (halfword: Off6 will be given as Off5<<1 from inst)
	op = 0b0101:
		bit[9]=0: {magic, op, L, B, Ro, Rb, Rd} (reg str/ldr: ldr r5, [r3, r0]
		bit[9]=1: {magic, op, H, S, Ro, Rb, Rd} (s'h' = strh, s'h = ldrh, sh' = ldsb, sh = ldsh)

	@param addr address of instruction to be decoded
	@return a valid instruction table or nil

]]
function decodeLSIntruction(addr)
	local inst = memory.readshort(addr)
	local output = nil -- invalid instruction, unless one of the following matches
	
	local Rb = bit.lshift(7, 3)
	local Rd = 7
	if authInstruction(inst, IMM, 3) then
		local B = bit.lshift(1, 12)
		local L = bit.lshift(1, 11)
		local off5 = bit.lshift(31, 6)
		output = {}
		output["magic"] = IMM
		output["op"] = bit.rshift(IMM, 13)
		output["B"] = bit.rshift(bit.band(inst, B), 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		if output["B"] == 1 then
			output["Off5"] = bit.rshift(bit.band(inst, off5), 6)
		elseif output["B"] == 0 then
			output["Off7"] = bit.lshift(bit.rshift(bit.band(inst, off5), 6), 2)
		else
			print([[ERROR: inst["B"] is neither 0 nor 1!]])
		end
		output["Rb"] = bit.rshift(bit.band(inst, Rb), 3)
		output["Rd"] = bit.band(inst, Rd)
	elseif authInstruction(inst, IMM_H, 4) then
		local L = bit.lshift(1, 11)
		local off6 = bit.lshift(31, 6)
		output = {}
		output["magic"] = IMM_H
		output["op"] = bit.rshift(IMM, 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		output["Off6"] = bit.lshift(bit.rshift(bit.band(inst, off6), 6), 1)
		output["Rb"] = bit.rshift(bit.band(inst, Rb), 3)
		output["Rd"] = bit.band(inst, Rd)
	elseif authInstruction(inst, REG, 4) then
		-- TODO: test
		local L = bit.lshift(1, 11)
		local B = bit.lshift(1, 10)
		local Ro = bit.lshift(7, 6)
		output = {}
		output["magic"] = REG
		output["op"] = bit.rshift(IMM, 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		output["B"] = bit.rshift(bit.band(inst, B), 10)
		output["Rb"] = bit.rshift(bit.band(inst, Ro), 6)
		output["Rb"] = bit.rshift(bit.band(inst, Rb), 3)
		output["Rd"] = bit.band(inst, Rd)
	elseif authInstruction(inst, REG_H, 4) then
		-- TODO: test
		local H = bit.lshift(1, 11)
		local S = bit.lshift(1, 10)
		local Ro = bit.lshift(7, 6)
		output = {}
		output["magic"] = REG_H
		output["op"] = bit.rshift(IMM, 12)
		output["H"] = bit.rshift(bit.band(inst, H), 11)
		output["S"] = bit.rshift(bit.band(inst, S), 10)
		output["Rb"] = bit.rshift(bit.band(inst, Ro), 6)
		output["Rb"] = bit.rshift(bit.band(inst, Rb), 3)
		output["Rd"] = bit.band(inst, Rd)
	end

	return output
end


--[[
	Decodes a push/pop instruction and returns a table with fields from the inst.
	op can be found to be the 4 MSB in the instruction. 
	All keys are strings.
	op = 0b1011: {magic, op, L, R, Rlist}
	L: (0 - push), (1 - pop).
	R: (0 - do not store LR/load PC), (1 - store LR/load PC)
	Rlist: This will be 7 bits. Each are flags for the registers r0-r7 to be pushed/popped.
	ex: Rlist=0b01010001 pushes or pops r0, r4, and r6.

	@param addr address of instruction to be decoded
	@return a valid instruction table or nil
]]
function decodePushPopInst(addr)
	local inst = memory.readshort(addr)
	local output = nil -- invalid instruction, unless one of the following matches
	
	if authInstruction(inst, PUSHPOP, 4) then
		local L = bit.lshift(1, 11)
		local R = bit.lshift(1, 8)
		local Rlist = 0xFF
		output = {}
		output["magic"] = PUSHPOP
		output["op"] = bit.rshift(PUSHPOP, 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		output["R"] = bit.rshift(bit.band(inst, R), 8)
		output["Rlist"] = bit.band(inst, Rlist)
	end
	
	return output

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
		inst = decodePushPopInst(curr)
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
	Confirms that magic matches by ANDING the instruction with the magic
	and confirming that only the magic remains.
	It also checks if op matches.
	@param inst the 2 bytes instruction to be authenticated
	@param magic the magic that must be set in the instruction
	@param opSize number of MSB bits the op is in the magic
	@return true if all tests pass, false otherwise
]]
function authInstruction(inst, magic, opSize)
	local op = bit.rshift(magic, 16 - opSize)
	local output = true
	if bit.band(inst, magic) ~= magic then
		output = false
	end
	if bit.rshift(inst, 16 - opSize) ~= op then
		output = false
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
