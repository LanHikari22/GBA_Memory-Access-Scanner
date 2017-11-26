--
-- User: Lan
-- Date: 11/26/2017
-- Time: 5:38 AM
-- This is a generic tester lua module. It shall test all modules to ensure correct functionality
--

-- Freespace Address to write testing instances in for testing. This should not be changed by the game...
-- Minimum free space: 64 bytes.
FS_ADDR = 0x02050000

require "InstructionDecoder"


--[[
    Main entrypoint for testing functions.
 ]]
function main()
    printTT(testInstructionDecoder())
end

-- InstructionDecoder Module ------------------------------------------------------------------------
--[[
    This function tests the InstructionDecoder module and makes sure it's working properly.
    If it's not,
 ]]
function testInstructionDecoder()
    local TT = {name="testInstructionDecoder()", subtests={}, passed=nil}
    table.insert(TT.subtests, test_decode_LdrStr())
    table.insert(TT.subtests, test_decode_PushPop())
    return determinePass(TT)
end

function test_decode_LdrStr()
   local TT = {name="decode_LdrStr()", subtests={}}

    -- Instance 1: LDR R0, [R1, #0x44] (0x6C48)
    memory.writeshort(FS_ADDR, 0x6C48)
    local inst = InstDecoder.decode_LdrStr(FS_ADDR)
    local passed=(
    inst.magic == InstDecoder.IMM
    and inst.op == 3
    and inst.B == 0 -- not LDRB
    and inst.L == 1 -- LDR
    and inst.offset == 0x44
    and inst.Rb == 1
    and inst.Rd == 0
    )
    if not passed then table.insert(TT.subtests, {name="[1]", passed=false}) end

    -- Instance 2: STRB R4, [R7, #0x19] (0x767C)
    memory.writeshort(FS_ADDR, 0x767C)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.IMM
    and inst.op == 3
    and inst.B == 1 -- stores byte
    and inst.L == 0 -- STR
    and inst.offset == 0x19
    and inst.Rb == 7
    and inst.Rd == 4
    )
    if not passed then table.insert(TT.subtests, {name="[2]", passed=false}) end

    -- Instance 3: LDR R7, [R5, 0x1C] (0x69EF)
    memory.writeshort(FS_ADDR, 0x69EF)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.IMM
    and inst.op == 3
    and inst.B == 0
    and inst.L == 1
    and inst.offset == 0x1C
    and inst.Rb == 5
    and inst.Rd == 7
    )
    if not passed then table.insert(TT.subtests, {name="[3]", passed=false}) end

    -- Instance 4: LDRH R3, [R5, #0x8] (0x892B)
    memory.writeshort(FS_ADDR, 0x892B)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.IMM_H
    and inst.op == 8
    and inst.L == 1
    and inst.offset == 0x8
    and inst.Rb == 5
    and inst.Rd == 3
    )
    if not passed then table.insert(TT.subtests, {name="[4]", passed=false}) end

    -- Instance 5: STRH R0, [R0] (0x8000)
    memory.writeshort(FS_ADDR, 0x8000)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.IMM_H
    and inst.op == 8
    and inst.L == 0
    and inst.offset == 0x00
    and inst.Rb == 0
    and inst.Rd == 0
    )
    if not passed then table.insert(TT.subtests, {name="[5]", passed=false}) end

    -- Instance 6: STRH R0, [R0, #0x34] (0x8680)
    memory.writeshort(FS_ADDR, 0x8680)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.IMM_H
    and inst.op == 8
    and inst.L == 0
    and inst.offset == 0x34
    and inst.Rb == 0
    and inst.Rd == 0
    )
    if not passed then table.insert(TT.subtests, {name="[6]", passed=false}) end

    -- Instance 7: LDR R0, [R1, R2] (0x5888)
    memory.writeshort(FS_ADDR, 0x5888)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.REG
    and inst.op == 5
    and inst.L == 1
    and inst.B == 0
    and inst.Ro == 2
    and inst.Rb == 1
    and inst.Rd == 0
    )
    if not passed then table.insert(TT.subtests, {name="[7]", passed=false}) end

    -- Instance 8: STRB R7, [R0, R6] (0x5587)
    memory.writeshort(FS_ADDR, 0x5587)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.REG
    and inst.op == 5
    and inst.L == 0
    and inst.B == 1
    and inst.Ro == 6
    and inst.Rb == 0
    and inst.Rd == 7
    )
    if not passed then table.insert(TT.subtests, {name="[8]", passed=false}) end

    -- Instance 9: STRH R5, [R3, R0] (0x521D)
    memory.writeshort(FS_ADDR, 0x521D)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.REG_H
    and inst.op == 5
    and inst.H == 0
    and inst.S == 0
    and inst.Ro == 0
    and inst.Rb == 3
    and inst.Rd == 5
    )
    if not passed then table.insert(TT.subtests, {name="[9]", passed=false}) end

    -- Instance 10: LDRH R2, [R4, R7] (0x5BE2)
    memory.writeshort(FS_ADDR, 0x5BE2)
    inst = InstDecoder.decode_LdrStr(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.REG_H
    and inst.op == 5
    and inst.H == 1
    and inst.S == 0
    and inst.Ro == 7
    and inst.Rb == 4
    and inst.Rd == 2
    )
    if not passed then table.insert(TT.subtests, {name="[10]", passed=false}) end

    return determinePass(TT)
end

function test_decode_PushPop()
    local TT = {name="decode_PushPop()", subtests={}, passed=true }
    math.randomseed(os.time())

    -- Instance 1: push {rx-ry}
    local randByte = math.random(0,255)
    memory.writeshort(FS_ADDR, bit.bor(0xB400, randByte))
    local inst = InstDecoder.decode_PushPop(FS_ADDR)
    local passed=(
    inst.magic == InstDecoder.PUSHPOP
    and inst.op == 0xB
    and inst.L == 0 -- push
    and inst.R == 0 -- no pc/lr
    and inst.Rlist == randByte
    )
    if not passed then table.insert(TT.subtests, {name="[1]", passed=false}) end

    -- Instance 2: push {rx-ry}
    memory.writeshort(FS_ADDR, bit.bor(0xB400, randByte))
    inst = InstDecoder.decode_PushPop(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.PUSHPOP
    and inst.op == 0xB
    and inst.L == 0 -- push
    and inst.R == 0 -- no pc/lr
    and inst.Rlist == randByte
    )
    if not passed then table.insert(TT.subtests, {name="[2]", passed=false}) end

    -- Instance 2: push {rx-ry, lr}
    memory.writeshort(FS_ADDR, bit.bor(0xB500, randByte))
    inst = InstDecoder.decode_PushPop(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.PUSHPOP
    and inst.op == 0xB
    and inst.L == 0 -- push
    and inst.R == 1 -- pc/lr
    and inst.Rlist == randByte
    )
    if not passed then table.insert(TT.subtests, {name="[2]", passed=false}) end

    -- Instance 3: pop {rx-ry}
    memory.writeshort(FS_ADDR, bit.bor(0xBC00, randByte))
    inst = InstDecoder.decode_PushPop(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.PUSHPOP
    and inst.op == 0xB
    and inst.L == 1 -- pop
    and inst.R == 0 -- no pc/lr
    and inst.Rlist == randByte
    )
    if not passed then table.insert(TT.subtests, {name="[2]", passed=false}) end

    -- Instance 4: pop {rx-ry, pc}
    memory.writeshort(FS_ADDR, bit.bor(0xBD00, randByte))
    inst = InstDecoder.decode_PushPop(FS_ADDR)
    passed=(
    inst.magic == InstDecoder.PUSHPOP
    and inst.op == 0xB
    and inst.L == 1 -- pop
    and inst.R == 1 -- pc/lr
    and inst.Rlist == randByte
    )
    if not passed then table.insert(TT.subtests, {name="[2]", passed=false}) end


    return determinePass(TT)
end

--[[
    Determines if a test passed by checking if all subtests have passed.
    @param TT   A test table. Its format is defined in printTT()
    @return the same table, but with passed=true or pased=false

 ]]
function determinePass(TT)
    if TT.subtests ~= nill then
        local passed = (TT.passed == nil) and true or TT.passed
        for k,test in pairs(TT.subtests) do
            passed = passed and test.passed
        end
        TT.passed = passed
    end
    return TT
end

--[[
    Recursively prints the Tests Table (TT) in the format:
    Test1... OK
        TEST1A... OK
        TEST1B... OK
    Test2... FAILED
        TEST2A... OK
        TEST2B... FAILED

    Tests Table: {name, subtests, passed},
    where name is the name of the test, subtests is a table of Test Tables, and passed is a boolean for passing.

    @param TT Test Table to print
 ]]
function printTT(TT)
    local level = 0
    recr_printTT(TT, level)
end

--[[
    prints the current test table and recursively calls itself to print all child test tables with an
    incremented level.

    @param TT table to recursively print
    @param level    The level of recursiveness, also used to determine space padding while printing
 ]]
function recr_printTT(TT, level)
    print(string.format("%s... %s", string.rep(" ", 4*level)..TT.name, TT.passed and "OK" or "FAILED"))
    if TT.subtests ~= nil then
        for k, test in pairs(TT.subtests) do
            recr_printTT(test, level + 1)
        end
    end
end

-- access entrypoint
main()