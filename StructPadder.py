##
# Author: Lan
# Description: This module's purpose is to pad incomplete structures so that they are usable. It also sorts the
# structure's members into correct order by consequence.
##
import re
POINTER_SIZE = 32 # size of a pointer in ARM7TDMI

##
# An entry represents one member in a C structure. One entry may look like this:
# "uint8_t someMember; // loc=0x04"
# It must consist of a type, name, and a location in the comments. Those propreties are defined in this class.
##
class StructMember:
    size: int          # Size of entry member. 8 for uint8_t, 32 for uint32_t, 32 for BANANA*, etc.
    type: str          # The first string in the entry for output reconstruction May include a star.
    name: str          # The name of the member.  May include a star: BANANA *b;
    location: int      # The location as extracted from the loc=<location> argument in the comment.
    otherContent: str  # Any more text that comes after // loc=<location>

    ##
    # Initiates the entry with a type, name, and location.
    # This is parted from strings passed in that are found in the input file.
    # If the entry is a POINTER, its type is still passed in but its size is automatically set to POINTER_SIZE
    # @param _type This is the type of the member, ex. (uint8_t) or (longSword*)
    # @param name The name of the member. If it contains *, the member is regarded as a pointer, like _type.
    # @param location
    ##
    def __init__(self, _type: str, name: str, location: int, otherContent: str):
        self.type = _type
        if('*' in name or '*' in _type):
            self.size = POINTER_SIZE
        else:
            self.size = int(re.search(r"\d+", _type).group()) # finding size in uint<size>_t
        self.name = name
        self.location = location
        self.otherContent = otherContent

##
# This finds out the whether a psssed maxLen, or the length of the line until '//' is greater.
# This is used to compute the maximum length of an entry until the comment. It is executed for all
# lines, and the very maximum Length will be the one outputted in the end.
##
def computeMaxLen(maxLen, line):
    # compute the maximum length just before //
    length = maxLen
    if "//" in line:
        cutoffIndex = line.index("//")
        if cutoffIndex > maxLen:
            length = cutoffIndex
    return length


##
# Parses a line with the form "uint<size>_t <name>; // loc=<location> (any arbitrary comments may be added on the line)
# A pointer of any type might also be passed: "BANANA *b; // loc=0x08" for example is valid.
# It is expected that after the last member definition line, a size is padded in the form
# "// size=0x1B0" for example. The entries may have a "uint8_t pad<loc>[]", but those are automatically ignored.
# Since pads are recompiled with the known entries which are also put into correct order.
# WARNING: Pads must not contain any comments other than // loc=<location>,
# as any line containing a pad is removed. All pads are recompiled after parsing in the program.
# @returns An array specifying the list an entry or the size of the struct. [Entry, 0] or [None, size].
##
def parse(line: str):
    args = list(filter(None, re.split("[ \t]", line)))
    entry = None
    structSize = 0
    # In case this is a line specifying size
    if len(args) == 2 and args[1][0:5] == "size=":
        structSize = int(args[1][5:], 16)
    # This may be an entry, or it may be a line that is not related. We also completely ignore pads.
    if len(args) >= 4 and (args[1][0:3] != "pad") and (args[3][0:4] == "loc="):
        valid = True
        # determine other content after args[3]
        extrContIndex = line.index(args[3]) + len(args[3])
        # construct entry. If there's extra text, there's a new line. Don't include that.
        entry = StructMember(args[0], args[1], int(args[3][4:], 16), line[extrContIndex:-1])

    return [entry, structSize]

##
# This function is used in sorted() so that the entries are compared based on their locations.
##
def compareLocations(entry):
    return entry.location

##
# This inserts pads into the entries list so that its locations are consistent. This makes the structure usable.
# The amount of padding is determined by three things: The current entry's location and size, and the next entry's
# location. If no next entry exists, it uses the structSize as the maximum "next location" for the pad.
##
def pad(entries, structSize):
    if len(entries) < 1:
        print("There are no entries to pad.")
        return
    i = 0
    while i < len(entries):
        # ignore if the entry is a pad.
        if entries[i].name[0:3] == "pad":
            # if it's the last entry, just leave
            if i == len(entries) - 1:
                break
            # ignore this newly inserted entry!
            i += 1
            continue
        # compute pad amount
        curr = entries[i]
        if i != len(entries) - 1:
            next = entries[i+1]
            padAmount = next.location - (curr.location + curr.size//8)
        else:
            padAmount = (structSize) - (curr.location + curr.size//8)
            if structSize == 0: padAmount = 0
        # add a pad if needed
        if padAmount != 0:
            entry = StructMember(_type="uint8_t", name="pad_%X[0x%X];" % (curr.location + curr.size // 8, padAmount),
                                 location=(curr.location + curr.size//8), otherContent = '')
            entries.insert(i+1, entry)
        # advance!
        i += 1

##
# Handles the parsing of an entry line or a line containing size. Other unrelated lines are ignored
# by the parser. The structSize output is most of the time zero until the size is actually parsed, therefore
# it should only be recorded when it's none-zero. maxLen is needed to go into this function again to compute
# for padding.
##
def handleLineParsing(entries, line, maxLen):
    maxLen = computeMaxLen(maxLen, line)
    structSize = 0
    parserOutput = parse(str(line))
    if parserOutput[0]:
        entries.append(parserOutput[0])
    if parserOutput[1] != 0:
        structSize = parserOutput[1]
    return structSize, maxLen


##
# Outputs the given entries, and the struct size in the end in a fashionable fashion.
##
def output(entries, maxLen, structSize):
    for entry in entries:
        s = ""
        # if it's a pad, tab twice... it looks pretty!
        if entry.name[0:3] == "pad":
            s += "\t\t"
        else:
            s += "\t"
        # format entry, with some smart tabbing and stuff
        s += "%s %s " % (entry.type, entry.name)
        s += " "*((maxLen) - len(s)) + "// loc=0x%X%s" % (entry.location, entry.otherContent)
        # output entry
        print(s)
    # output size
    if structSize != 0:
        print("\t// size=0x%X" % structSize, end='')




##
# This program takes in member definitions for a structure, and applies pads as appropriate so that the structure
# is usable. All previous pads are recompiled when this program is run on the input.
# Let this program handle padding for you. The requirement is that the entries are defined like this:
# "uint32_t[*] [*]name; [tabbing...] // loc=<location in hex>
# Allowed types: uint8_t, uint16_t, and uint32_t. uint<size>_t should be parsable in theory.
# pointers of all type are also allowed. Where the star is put does not matter. It can be put in both places,
# this program won't check for that. If it detects a star, it automatically associates the entry with a size of
# POINTER_SIZE.
##
if __name__ == "__main__":
    inputFile = open("input", "r")
    line = '\0'
    structSize = 0
    entries = []
    maxLen = 0
    while line != '':
        line = inputFile.readline()
        tempStructSize, maxLen = handleLineParsing(entries, line, maxLen)
        if tempStructSize != 0:
            structSize = tempStructSize
    print(structSize)
    entries = sorted(entries,key=compareLocations, reverse=False)
    pad(entries, structSize)
    output(entries, maxLen, structSize)