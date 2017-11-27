--
-- User: Lan
-- Date: 11/26/2017
-- Time: 12:48 PM
-- This module's purpose is to figure things the MemoryAccessDetector could not figure out immediately.
-- Such as funcion addresses that are not so apparent as well as accesses with register offsets.
--

require "InstructionDecoder" -- InstDecoder

-- This module's table
FuncRxm = {}

-- Those queues determine what must be handled. Those are special cases that needs to be taken care of.
FuncRxm.regOffQueue = {} -- any encountered accesses with register offsets go here
FuncRxm.funcAddrQueue = {} -- any encountered accesses with unknown function addresses go here
FuncRxm.callbackQueue = {} -- Any access that is actually called through callback needs a second round

--[[
    When a function with an unknown function address is detected,
    Find a return mechanism (pop {..., pc} or pop{rx} bx rx or mov pc, lr) both above, and below the current
    address. The one above is used to compute a range rx would be in for callback, while
    the lower one would be used to obtain the location of the call.
    In case the call is a bx rx, the location is known immediately.
    If the call is a pop {pc}, or a pop {..., pc}, lr is extracted from the stack.
    A handler is then registered where the call occurs to obtain the address of the current function.
    In case it is in rx, the value has to be in the range between the access address
    and the above return address.

    @param addr address of access
 ]]
FuncRxm.addUnkFuncAddr = function(pc, funcAddr, utype_str, offset_str)
    -- TODO: standard printing... for now
    local msg = string.format("%s::%08X %s(%s)", funcAddr, pc, utype_str, offset_str)
    if printToScreen then
        vba.message(msg)
    end
    -- print everytime there are entriesPerLine entries in the line
    local endline = true
    if #STR_entries % entriesPerLine == 0 then
        printSameLine(msg..", ", endline)
    else
        printSameLine(msg..", ", not endline)
    end


--    print(string.format("Detected Mysterious Access (Function): 0x%X", pc))
    local above = true
    local aboveReturnAddr = FuncRxm._findNearestReturn(pc,above)
    local belowReturnAddr = FuncRxm._findNearestReturn(pc,not above)
    -- now break on the execution of a return: this will in turn also break on a write...
    memory.registerexec(belowReturnAddr, FuncRxm._handleFuncCaller)
    -- Add all information into the queue so it's available to the handler
    table.insert(FuncRxm.funcAddrQueue, {pc, funcAddr, belowReturnAddr, utype_str, offset_str})
--    print(string.format("%X - %X", aboveReturnAddr, belowReturnAddr))
end

FuncRxm._handleFuncCaller = function()
--    print(string.format("In handler: %X", memory.getregister('r15')-4))
--    vba.pause()
end

--[[
    Since the offset register has been overwritten by the execution of this access,
    We register a handler to the execution of the instruction just before to obtain the offset register.
    @param addr address of access
 ]]
FuncRxm.addUnkRegOff = function(pc, funcAddr, utype_str, offset_str)
    -- TODO: standard printing... for now
    local msg = string.format("%s::%08X %s(%s)", funcAddr, pc, utype_str, offset_str)
    if printToScreen then
        vba.message(msg)
    end
    -- print everytime there are entriesPerLine entries in the line
    local endline = true
    if #STR_entries % entriesPerLine == 0 then
        printSameLine(msg..", ", endline)
    else
        printSameLine(msg..", ", not endline)
    end

--    print(string.format("Detected Mysterious Access (Register): %s::0x%X", funcAddr, pc))
end

FuncRxm._findNearestReturn = function(addr, above)
    local curr = addr
    local output = -1
    local step = above and -2 or 2
	local stillSearching = true
	while stillSearching do
        -- if curr instruction is a pop {..., pc}
        local inst = InstDecoder.decode_PushPop(curr)
		if inst ~= nil and inst.R == 1 then
			stillSearching = false
			if inst["L"] == 1 then
                output = curr
            else
                if above then -- Shouldn't be able to find a normal start to the function.
                    print(string.format("ERROR (@0x%X) Encountered func address even though MemoryAccessDetector didn't", curr))
                end
			end
        end
        -- if curr instruction is a mov pc, lr
        local inst = memory.readshort(curr)
        if inst == InstDecoder.MOV_PC_LR then
            stillSearching = false
            output = curr
        end
        -- if curr is bx lr
        local instBx = InstDecoder.decode_bx(curr)
        if instBx ~= nil and instBx.Rx == 14 then
            stillSearching = false
            output = curr
        end
        -- if curr instructions are pop {rx} bx
        local instBx = above and InstDecoder.decode_bx(curr) or InstDecoder.decode_bx(curr+2)
        local instPop = above and InstDecoder.decode_PushPop(curr-2) or InstDecoder.decode_PushPop(curr)
        if instBx ~= nil and instPop ~= nil and instPop.R == 0 and instPop.L == 1 then
            -- if Rlist contains Rx, this is a return mechanism
            if bit.band(instPop.Rlist, bit.lshift(1,instBx.Rx)) ~= 0 then
            stillSearching = false
            output = above and curr or curr+2
            end
        end

		curr = curr + step
	end
	return output

end