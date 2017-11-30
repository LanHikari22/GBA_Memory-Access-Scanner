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

-- Those tables determine what must be handled. Those are special cases that needs to be taken care of.
FuncRxm.processTable = {} -- any accesses that require more investigation on their offsets/func addresses
FuncRxm.readyTable = {} -- Accesses that have been processed already! The MemoryAccessDetector module takes these back
-- Format of access entries: {entryType={func=true/false, reg=true/false},handlerAddresses, pc, funcAddr, utype_str, offset_str}}

--[[
    This must be called on all access entries that were not investigated fully such as if
    the function address is not known fully, or if the offset is unknown.
    This module attempts to reexamine them and determine what is missing.
 ]]
FuncRxm.registerForReexamination = function(pc, funcAddr, utype_str, offset_str)
    -- print
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


--    if string.find(funcAddr, "?") ~= nil then
--        FuncRxm._setupUnkFuncAddrHandler(pc, funcAddr, utype_str, offset_str)
--    end
--    if string.find(offset_str, "?") ~= nil then
--        FuncRxm._setupUnkRegOffHandler(pc, funcAddr, utype_str, offset_str)
--    end
end

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
FuncRxm._setupUnkFuncAddrHandler = function(pc, funcAddr, utype_str, offset_str)

--    print(string.format("Detected Mysterious Access (Function): 0x%X", pc))
    local above = true
    local belowReturnAddr = FuncRxm._findNearestReturn(pc,not above)
    -- now break on the execution of a return: this will in turn also break on a write...
    memory.registerexec(belowReturnAddr, FuncRxm._handleFuncCaller)
    -- Add all information into the queue so it's available to the handler
    FuncRxm.addToProcessTable({entryType={func=true, reg=false},handlerAddresses={belowReturnAddr},
        pc, funcAddr, utype_str, offset_str})
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
FuncRxm._setupUnkRegOffHandler = function(pc, funcAddr, utype_str, offset_str)
    -- TODO: standard printing... for now
    print(string.format("Detected Mysterious Access (Register): %s::%X", funcAddr, pc))
    print(string.format("r4=%08X", memory.getregister("r4")))
    -- Set a handler to be executed one instruction before, to retrieve missing offset information
    memory.registerexec(pc, FuncRxm._handleRetrievingRegOffset)
    -- Add entry to the processTable to be processed by the handler
    FuncRxm.addToProcessTable({entryType={func=false, reg=true}, handlerAddresses={pc},
        pc, funcAddr, utype_str, offset_str})

end

FuncRxm._handleRetrievingRegOffset = function()
    local pc = memory.getregister("r15") - 4
    if not FuncRxm.inArray(pc, FuncRxm.readyTable) then
        table.insert(FuncRxm.readyTable, pc)
        print(string.format("Hit register handler: %08X", pc))
        print(string.format("r4=%08X", memory.getregister("r4")))

    end

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

--[[
    This function is to be called by the MemoryaccessDetector module to register that the requested special case
    entries it requested have been already processed. It also outputs those entries.

    @param entries A table of Access addresses, it is appended to so that the MAD module ignores that address in the future
    @return the entries, but with all processed entries accounted for
 ]]
FuncRxm.retrieveProcessedEntries = function(entries)
    for k,entry in ipairs(FuncRxm.readyTable) do
        print("FuncRxm.retrieveProcessedEntries executes~")
        table.insert(entries,entry.pc)
    end
    FuncRxm.readyTable = {}
    return entries
end

FuncRxm.addToProcessTable = function(accessEntry)
    local entryKey = FuncRxm._getEntryKey({entry=accessEntry})
    if entryKey == nil then
        table.insert(FuncRxm.processTable, accessEntry)
    else
        -- Set extra entry type, originally it was only one: now it's two that are set
        if accessEntry.entryType.func then
            FuncRxm.processTable[entryKey].entryType.func = true
        end
        if accessEntry.entryType.reg then
            FuncRxm.processTable[entryKey].entryType.reg = true
        end

        -- add the new handlers to the entry
        for k, handlerAddr in ipairs(accessEntry.handlerAddresses) do
           table.insert(FuncRxm.processTable[entryKey].handlerAddresses, handlerAddr)
        end
    end
end

--[[
    Given the program pointer for a handler, or a similar access entry (same PC)

    @param inTbl Either specify a handler address, or an entry:
            {handlerAddr=...} or {entry=...}
    returns the key for the associated access entry from the process table or nil
 ]]
FuncRxm._getEntryKey = function(inTbl)
    local output
    for k0, accessEntry in ipairs(FuncRxm.processTable) do
            if inTbl.handlerAddr ~= nil and inTbl.entry == nil then
                for k1, AEHandlerAddr in ipairs(accessEntry.handlerAddresses) do
                    -- If at least one handler address matches in both, this is the entry desired
                    if AEHandlerAddr == inTbl.handlerAddr then
                        output = k0
                    end
                end
            elseif inTbl.handlerAddr == nil and inTbl.entry ~= nil then
                if accessEntry.pc == inTbl.entry.pc then
                    -- Same access address, therefore this is the desired entry!
                   output = k0
                end
            end
    end
    return output
end

--[[
 Returns whether the value <value> is in the array <arr>
 @param value	value to check for
 @param arr		array to check for value in
 @return whether the value was in the array
]]
FuncRxm.inArray = function(value, arr)
	local wasThere = false
	for k,v in ipairs(arr) do
		if v == value then
			wasThere = true
		end
	end
	return wasThere
end