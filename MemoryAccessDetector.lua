require "InstructionDecoder" -- InstDecoder
require "FunctionReexaminer" -- FuncRxm
-- Module Input ------------------------------------------------------------------
-- Base register of block to Log writes/reads of (ex. 0x02000000)
base = 0x02001B80
-- The size of the memory block (ex. 0x22)
size = 0x84
-- In case the block of memory (or struct) has a name. Useful for other programs
name = "s_02001B80"
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

-- Globals ----------------------------------------------------------------------
-- Memory accesses detected for write
detectedEntries = {}
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
			registerStructWrite(base, size, detectAccess)
		end
		if detectReads then
			registerStructRead(base, size, detectAccess)
		end
		vba.frameadvance()
	end
end

-- TODO: debug: This just doesn't fire. I don't know why.
function main1()
    while true do
        memory.registerexecute(0x802A6EA , veep)
        vba.frameadvance()
    end
end

function veep()
    print("veep")
    vba.pause()
end

--[[
 the function func is called whenever a write to the structure at address addr is detected
]]
function registerStructWrite(addr, size, func)
	for i=addr,addr+size-1 do
		memory.registerwrite(i, func)
	end
end

--[[
 the function func is called whenever a read to the structure at address addr is detected
]]
function registerStructRead(addr, size, func)
	for i=addr,addr+size-1 do
		memory.registerread(i, func)
	end
end


--[[
	This assumes that the write to be detected is in THUMB mode.
]]
function detectAccess()
	local pc = memory.getregister("r15") - 4  -- -4 due to pipelining
	local inst = InstDecoder.decode_LdrStr(pc)

	if not FuncRxm.inArray(pc, detectedEntries) and inst ~= nil then

        table.insert(detectedEntries, pc) -- when encountering this again, just ignore it.
		local funcAddr = findFuncAddr(pc)
		local utype = getType(inst)
		local utype_str = (utype ~= -1) and "u"..utype or "?"
		local offset_str = getOffset(inst, pc)

        -- If the function address or the access offset are unknown, set this up for reexamination
        if string.find(funcAddr, "?") or string.find(offset_str, "?") ~= nil then
            if pc == 0x8035938 then
                printState()
            end
            FuncRxm.registerForReexamination(pc, funcAddr, utype_str, offset_str)
        end

        -- Normal case, both function address and offset were detected easily
        if string.find(funcAddr, "?") == nil and string.find(offset_str, "?") == nil then
            local msg = string.format("%s::%08X %s(%s)", funcAddr, pc, utype_str, offset_str)
            if printToScreen then
                vba.message(msg)
            end
            -- print everytime there are entriesPerLine entries in the line
            local endline = true
            if #detectedEntries % entriesPerLine == 0 then
                printSameLine(msg..", ", endline)
            else
                printSameLine(msg..", ", not endline)
            end
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
	local output
	local stillSearching = true
	while stillSearching do
        -- if a push{..., lr} pr pop{..., pc} is encountered
		local inst = InstDecoder.decode_PushPop(curr)
		if inst ~= nil and inst["R"] == 1 then
			stillSearching = false
			if inst["L"] == 0 then -- yay detected a push {lr} before pop {pc}!
				output = string.format("%08X", curr)
            else -- pop {pc} before push {lr}? oops
                output = string.format("%08X?", curr+2)
			end
        end
        -- if curr instruction is a mov pc, lr: yikes.
        local inst = memory.readshort(curr)
        if inst == InstDecoder.MOV_PC_LR then
            stillSearching = false
            output = string.format("%08X?", curr+2)
        end
        -- if curr is bx lr
        local instBx = InstDecoder.decode_bx(curr)
        if instBx ~= nil and instBx.Rx == 14 then
            stillSearching = false
            output = string.format("%08X?", curr+2)
        end
        -- if curr instructions are pop{rx} bx: yikes
        local instBx = InstDecoder.decode_bx(curr)
        local instPop = InstDecoder.decode_PushPop(curr-2)
        if instBx ~= nil and instPop ~= nil and instPop.R == 0 and instPop.L == 1 then
            -- if Rlist contains Rx, this is a return mechanism
            if bit.band(instPop.Rlist, bit.lshift(1,instBx.Rx)) ~= 0 then
                stillSearching = false
                output = string.format("%08X?", curr+2)
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
	if inst["magic"] == InstDecoder.IMM or inst["magic"] == InstDecoder.REG then
		if inst["B"] == 0 then
			output = 32
		elseif inst["B"] == 1 then
			output = 8
		end
	elseif inst["magic"] == InstDecoder.IMM_H or inst["magic"] == InstDecoder.REG_H then
        if inst["S"] == 0 then
		    output = 16
        else
            output = 8
        end

	end
	return output
end

--[[
	Gets the offset of an LDR/STR instruction
	This must be executed when the ARM CPU is actually at pc.
	@param inst A table representing the decoded instruction
	@return the offset in the intruction if present
]]
function getOffset(inst, pc)
	local output = -1
    if inst ~= nil then
        -- Confirm Rb is not the same as Rd in order to correctly identify base
        local output_base
        local actual_base = memory.getregister("r"..inst["Rb"])
        output_base = (actual_base - base == 0) and '' or string.format("0x%02X+", actual_base - base)

--        if inst["Rb"] ~= inst["Rd"] then
--            local actual_base = memory.getregister("r"..inst["Rb"])
--            output_base = (actual_base - base == 0) and '' or string.format("0x%02X+", actual_base - base)
--        else
--            -- OK, One pattern is an LDR Rx=offset before an access
--            local prevInst = InstDecoder.decode_PCRel(pc-2)
--            if prevInst ~= nil and prevInst.Rd == inst.Rd then
--                -- next word from (pc-2) + pc_offset is where the base is loaded from
--                local actual_base = ((pc-2) % 4 == 0) and memory.readlong(pc + 2 + prevInst.pc_offset) or
--                    memory.readlong(pc + prevInst.pc_offset)
--                if actual_base - base == 0xA2E85D17 then print(string.format("BEEEEEEEEEEEEEEEP pc=%08X", pc + prevInst.pc_offset)) end
--                output_base =  (actual_base - base == 0) and '' or string.format("0x%02X+", actual_base - base)
--            else -- Unknown base address
--                output_base = "?+"
--            end
--        end

        -- In case the offset is an immediate
        if inst["magic"] == InstDecoder.IMM or inst["magic"] == InstDecoder.IMM_H then
            output = output_base..string.format("0x%02X", inst["offset"]) -- string.format("0x%02X", offset)
        -- In case the offset is a register
        elseif inst["magic"] == InstDecoder.REG or inst["magic"] == InstDecoder.REG_H then
            print("reg")
            output = output_base..string.format("0x%02X",memory.getregister("r"..inst["Ro"]))
--            if inst["Ro"] ~= inst["Rd"] then
--                output = output_base..string.format("0x%02X",memory.getregister("r"..inst["Ro"]))
--            else
--                -- Try to check above instruction. One pattern is a mov Ro, imm.
--                local prevInst = InstDecoder.decode_MovImm(pc-2)
--                if prevInst ~= nil and prevInst.Rd == inst.Ro then
--                    output = output_base..string.format("0x%02X", prevInst.imm)
--                end
--            end
        end
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
		local newLine = true
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
	local inputTable = input.get()
	if inputTable[lineReleaseKey] and line ~= '' then
		local newLine = true
		printSameLine('', newLine)
	end
end

function printState()
    local state = ''
    for i=0,15 do
        state = state..string.format("%08X ", memory.getregister("r"..i))
        if (i+1) % 4 == 0 then print(state); state = '' end
    end
end

main()
