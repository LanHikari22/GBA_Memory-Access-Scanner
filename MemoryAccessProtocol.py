##
# Author: Lan
# Description: The purpose of this module is to parse in the output of the VBA-rr lua script.
# It can also generate a template structure from the parsed information, and pads it using the StructPadder module
# so that it's a programmatically usable structure template.
##
import re
import StructPadder


class MemoryAccessEntry:
    functionAddr: str
    accessAddr: int
    type: int
    base: int
    offset: int
    def __init__(self, functionAddr, accessAddr, _type, base, offset):
        if type(functionAddr) is not str or type(accessAddr) is not int or \
                        type(_type) is not int and type(offset) is not int:
            raise(Exception("Invalid inputs to MemoryAccessEntry"))
        self.functionAddr = functionAddr
        self.accessAddr = accessAddr
        self.type = _type
        self.base = base
        self.offset = offset


class MemoryAccessProtocol:
    _MAEntries: list  # Memory Acesss Entries
    _SMEntries: list  # Struct Member Entries
    name: str
    size: int

    def __init__(self, metaLine):
        # parse relevent meta information
        args = list(filter(None, re.split("[ \t,]", metaLine)))
        for arg in args:
            if 'name=' in arg:
                self.name = arg[5:]
            if 'size=' in arg:
                self.size = int(arg[5:], 16)
        # instantiate entries
        self._MAEntries = []
        self._SMEntries = []


    def parseline(self, line):
        args = list(filter(None, re.split("[ \t,\n]", line)))
        # if this is an entry line, the first argument will always be in the form <funcAddr>::<accessAddr>
        if len(args) == 0:
            return
        if '::' not in args[0]:
            return
        if len(args) % 2 != 0:
            return
        # parse all entries in line!
        for i in range(0, len(args), 2):
            addresses = str(args[i])  # <funcAddr>::<accessAddr>
            memAccess = str(args[i+1])  # u<type>(<offset>)
            funcAddr = addresses[:addresses.index("::")]
            accessAddr = int(addresses[addresses.index("::")+2:], 16)
            type = int(re.search(r"\d+", memAccess[:memAccess.index("(")]).group())
            # Offset not identified, it cannot be used
            if "+" in memAccess:
                if "?" in memAccess:
                    base = -1
                    offset = int(memAccess[memAccess.index("+") + 1:-1], 16)
                else:
                    base = int(memAccess[memAccess.index("(")+1:memAccess.index("+")], 16)
                    offset = base + int(memAccess[memAccess.index("+") + 1:-1], 16)
            else:
                base = 0
                offset = int(memAccess[memAccess.index("(")+1:-1], 16)
            entry = MemoryAccessEntry(funcAddr,accessAddr,type,base, offset)
            self._MAEntries.append(entry)

    def generate_member_entries(self):
        self._SMEntries = []
        for MAEntry in self._MAEntries:
            if MAEntry.offset == -1: continue # cannot imply anything on structure members with these...
            SMEntry = StructPadder.StructMember(_type="uint%d_t" % MAEntry.type, name= "unk_%02X;" % MAEntry.offset,
                                                location= MAEntry.offset, otherContent='')
            self._SMEntries.append(SMEntry)
        # All duplicated of the same type are removed
        self.remove_duplicates()
        # there could be duplicates... with different types... mark them
        self.mark_loc_duplicates()
        # Remove all CONFLICT marked duplicates except for the one with the lowest size
        self.remove_loc_duplicates()
        # Now to pad. Things will go wrong if there are location duplicates.
        StructPadder.pad(self._SMEntries, self.size)

    def no_SMEntry_duplicate_in(self, newSMEntries, SMEntry):
        output = True
        for entry in newSMEntries:
            if entry.location == SMEntry.location and entry.type == SMEntry.type:
                output = False
        return output

    def remove_duplicates(self):
        # first, sort by location and by type...
        self._SMEntries = sorted(self._SMEntries, key= lambda x: (x.location, x.size), reverse=False)
        # remove duplicates base on type and location
        newSMEntries = []
        for entry in self._SMEntries:
            if self.no_SMEntry_duplicate_in(newSMEntries, entry):
                newSMEntries.append(entry)
        self._SMEntries = newSMEntries



    def mark_loc_duplicates(self):
        # first, sort by location and by type...
        self._SMEntries = sorted(self._SMEntries, key= lambda x: (x.location, x.size), reverse=False)
        # mark all location duplicates as CONFLICT
        for i in range(len(self._SMEntries)):
            if " CONFLICT" not in self._SMEntries[i].otherContent: # " CONFLICT" b/c spaces are included after loc=0x%X
                for j in range(i+1, len(self._SMEntries)):
                    if self._SMEntries[i].location == self._SMEntries[j].location:
                        if self._SMEntries[i].otherContent == '': self._SMEntries[i].otherContent = " CONFLICT"
                        self._SMEntries[j].otherContent = " CONFLICT"
                        self._SMEntries[i].otherContent += " u" + str(self._SMEntries[j].size)

    def remove_loc_duplicates(self):
        # This should only be called after marking, so sorting is guaranteed
        # The lowest CONFLICT has been marked with all the higher ones. " CONFLICT u16 u32" for example.
        # The higher ones were only marked with CONFLICT and could cause padding errors: remove them.
        newSMEntries = []
        for i in range(len(self._SMEntries)):
            if self._SMEntries[i].otherContent != " CONFLICT":
                newSMEntries.append(self._SMEntries[i])
        self._SMEntries = newSMEntries

    def output_struct_template(self):
        print('typedef struct{')
        maxLen = len('uint32_t unk_FFF     ')
        StructPadder.output(self._SMEntries,maxLen,self.size)
        print('\n}%s;' % self.name)

if __name__ == '__main__':
    inputFile = open("input", "r")
    line = inputFile.readline()
    memap = MemoryAccessProtocol(line) # parse meta information line
    while line != '':
        line = inputFile.readline()
        memap.parseline(line)
    memap.generate_member_entries()
    memap.output_struct_template()
