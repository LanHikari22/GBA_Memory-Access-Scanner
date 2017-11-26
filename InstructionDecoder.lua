-- Table of module
InstDecoder = {}

-- Global Definitions (wannabe, please don't change :'( )-----------------------------------
-- Magic to identify instructions
-- LDR/STR Magic
InstDecoder.IMM = 	  0x6000 -- 0b0110_0000_0000_0000
InstDecoder.IMM_H =   0x8000 -- 0b1000_0000_0000_0000
InstDecoder.REG = 	  0x5000 -- 0b0101_0000_0000_0000
InstDecoder.REG_H =	  0x5200 -- 0b0101_0010_0000_0000
-- PUSH/POP Magic
InstDecoder.PUSHPOP = 0xB400 -- 0b1011_0100_0000_0000



--[[
    This tries to decode any instruction at the given address, using available decode_<instType> functions.
    @param addr The address for the instruction to be decoded
    @return the decoded instruction or nil
 ]]
InstDecoder.decode = function(addr)
    local output = InstDecoder.decode_LdrStr(addr)
    if output == nil then
        output = InstDecoder.decode_PushPop(addr)
    end
    return output
end

--[[
	Decodes an Load/Store instruction and returns a table. Type dependent on op (and magic).
	Only loads/stores of the types "str r0, [r1, r2]" and "ldr r5, [r6, 0xFF]" are decoded.
	op is found in MSB 3 bits or 4 bits. 
	magic will be IMM, IMM_H, REG, or REG_H. Indicating halfword vs not, and immediate offset vs not.
	[InstDecoder.IMM]
	op = 0b011: {magic, op, B, L, offset, Rb, Rd} (B=byte, L=Load, Rb=Base Reg, Rd=Dest Reg)
	[InstDecoder.IMM_H]
	op = 0b1000: {magic, op, L, offset, Rb, Rd}
	[InstDecoder.REG, InstDecoder.REG_H]
	op = 0b0101:
	    [Instdecoder.REG]
		bit[9]=0: {magic, op, L, B, Ro, Rb, Rd} (reg str/ldr: ldr r5, [r3, r0]
		[InstDecoder.REG_H]
		bit[9]=1: {magic, op, H, S, Ro, Rb, Rd} (s'h' = strh, s'h = ldrh, sh' = ldsb, sh = ldsh)

	@param addr address of instruction to be decoded
	@return a valid instruction table or nil

]]
InstDecoder.decode_LdrStr = function(addr)
	local inst = memory.readshort(addr)
	local output = nil -- invalid instruction, unless one of the following matches
	
	local Rb = bit.lshift(7, 3)
	local Rd = 7
	if InstDecoder.authInstruction(inst, InstDecoder.IMM, 3) then
		local B = bit.lshift(1, 12)
		local L = bit.lshift(1, 11)
		local off5 = bit.lshift(31, 6)
		output = {}
		output["magic"] = InstDecoder.IMM
		output["op"] = bit.rshift(InstDecoder.IMM, 13)
		output["B"] = bit.rshift(bit.band(inst, B), 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		if output["B"] == 1 then
			output["offset"] = bit.rshift(bit.band(inst, off5), 6)
		elseif output["B"] == 0 then -- if B': Off7 will be Off5<<2 from inst)
			output["offset"] = bit.lshift(bit.rshift(bit.band(inst, off5), 6), 2)
		else
			print([[ERROR: inst["B"] is neither 0 nor 1!]])
		end
		output["Rb"] = bit.rshift(bit.band(inst, Rb), 3)
		output["Rd"] = bit.band(inst, Rd)
	elseif InstDecoder.authInstruction(inst, InstDecoder.IMM_H, 4) then
		local L = bit.lshift(1, 11)
		local off6 = bit.lshift(31, 6)
		output = {}
		output["magic"] = InstDecoder.IMM_H
		output["op"] = bit.rshift(InstDecoder.IMM_H, 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		output["offset"] = bit.lshift(bit.rshift(bit.band(inst, off6), 6), 1)
		output["Rb"] = bit.rshift(bit.band(inst, Rb), 3)
		output["Rd"] = bit.band(inst, Rd)
	elseif InstDecoder.authInstruction(inst, InstDecoder.REG_H, 4) then -- TODO: placement of this if is necessary
		-- TODO: test
		local H = bit.lshift(1, 11)
		local S = bit.lshift(1, 10)
		local Ro = bit.lshift(7, 6)
		output = {}
		output["magic"] = InstDecoder.REG_H
		output["op"] = bit.rshift(InstDecoder.REG_H, 12)
		output["H"] = bit.rshift(bit.band(inst, H), 11)
		output["S"] = bit.rshift(bit.band(inst, S), 10)
		output["Ro"] = bit.rshift(bit.band(inst, Ro), 6)
		output["Rb"] = bit.rshift(bit.band(inst, Rb), 3)
		output["Rd"] = bit.band(inst, Rd)
	elseif InstDecoder.authInstruction(inst, InstDecoder.REG, 4) then
		-- TODO: test
		local L = bit.lshift(1, 11)
		local B = bit.lshift(1, 10)
		local Ro = bit.lshift(7, 6)
		output = {}
		output["magic"] = InstDecoder.REG
		output["op"] = bit.rshift(InstDecoder.REG, 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		output["B"] = bit.rshift(bit.band(inst, B), 10)
		output["Ro"] = bit.rshift(bit.band(inst, Ro), 6)
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
InstDecoder.decode_PushPop = function(addr)
	local inst = memory.readshort(addr)
	local output = nil -- invalid instruction, unless one of the following matches
	
	if InstDecoder.authInstruction(inst, InstDecoder.PUSHPOP, 4) then
		local L = bit.lshift(1, 11)
		local R = bit.lshift(1, 8)
		local Rlist = 0xFF
		output = {}
		output["magic"] = InstDecoder.PUSHPOP
		output["op"] = bit.rshift(InstDecoder.PUSHPOP, 12)
		output["L"] = bit.rshift(bit.band(inst, L), 11)
		output["R"] = bit.rshift(bit.band(inst, R), 8)
		output["Rlist"] = bit.band(inst, Rlist)
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
InstDecoder.authInstruction = function(inst, magic, opSize)
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