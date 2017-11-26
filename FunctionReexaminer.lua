--
-- User: Lan
-- Date: 11/26/2017
-- Time: 12:48 PM
-- This module's purpose is to figure things the MemoryAccessDetector could not figure out immediately.
-- Such as funcion addresses that are not so apparent as well as accesses with register offsets.
--

-- This module's table
FuncRxm = {}

-- Those queues determine what must be handled. Those are special cases that needs to be taken care of.
FuncRxm.regOffQueue = {} -- any encountered accesses with register offsets go here
FuncRxm.funcAddrQueue = {} -- any encountered accesses with unknown function addresses go here
FuncRxm.callbackQueue = {} -- Any access that is actually called through callback needs a second round