# GBA_Memory-Access-Scanner

<b>[ Description ---------------------------]</b>

This program automates the process of setting watchpoints to detect functions accessing a structure or block of memory.
It is capable of presenting all detected functions that write and read from a block of memory or structure.
It detects access types (ldr having a type of 32, strh having a type of 16, ldrb having a type of 8, etc) 
and access offsets (str r0, [r5, 0x35] 0x35, being the offset)

Through detected access types and offsets, the program can generate a typedef structure template for the structure itself.
However, correctly estimating the size of a structure is very critical for the generation of the template.
Underestimating is OK, but overestimating is bad.

Sometimes, the game may access a memory location inconsistently. This causes problems in the generation
of a structure template, which generates false structure padding. In such a case, all relevent entries are marked as
CONFLICT in the structure template output. By fixing these conflicts manually (by choosing only one
and removing the other duplicates), the template may be input into the StructPadder module to fix the padding.

<b>[ Protocol ------------------------------]</b>

Setting up and running the MemoryAccessDetector.lua in VBA-rr and doing relevent actions to the structure in game
should generate output that looks like this:
```
name=s_02001B80, size=0x84
080050EC::080050F4 u8(0x00), 08035932::08035938 u8(0x06), 0809F99A::0809F9A0 u8(0x10), 
0809DEA0::0809DEC0 u8(0x04), 08034EF0::08034EFC u8(0x0E), 08034F68::08034F74 u32(0x18),
```
The first line contains meta information important to the MemoryAccessProtocol module.
The next lines contain a repeating pattern of entries that describe a memory access.
The format is: <function_Address>::< Memory_Access_Address> u<type_of_access>(<Offset_of_access>)
The program attempts to find the function address by searching for a push {..., lr} somewhere above.
If it detects a pop {..., pc} first, it indicates that the function address is unkown by placing a  '?' in its location.

<b>[ Usage ----------------------------------]</b>
1. Configure the MemoryAccessDetector.lua file by 
  1a. setting the base address and the size, and name of the structure.
  1b. setting whether to scan on reads (LDRs) or writes (STRs) or both (or neither, oh well).
2. Run the script in VBA-rr while playing the relevent game you're trying to scan.
  2a. Perform actions you think are relevent to the structure to get a better output.
  2b. (By default) Press 'P' after you're done to make sure all memory access entries have been outputted.
3. Copy the output of the lua script into the file "input".
4. Run the MemoryAccesProtocol.py module to generate a structure template in stdout.

In case the structure template containts CONFLICTS:
1. Manually go through each conflict, and remove duplicates 
(structure members of the same location yet different types).
2. (optional): Remove the tag " CONFLICT" from the entry. so that the only comment is "// loc=0x22" for example.
3. Copy the content of the template and put it in the "input" file. 
    (minus the "typdef struct{" lines and "}structName;" lines)
4. Run the StructPadder.py module to get correct padding.

<b>[ Dependencies ------------------------------]</b>
1. VBA-rr
2. Python3
3. A GBA ROM to scan
