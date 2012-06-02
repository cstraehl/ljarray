local narray = require("narray")

local bcount = 1000

local ta = narray.create({100,100,100}, narray.int32)
local tb = narray.create({100,100,100}, narray.int32)
local tc = narray.create({100,100,100}, narray.int32)

helpers.benchmark(function()  local blubb = narray.create({100,100,100}, narray.int32) end, bcount, "allocate array")

ta:assign(1)
tb:assign(1)
local func =  function(a, pos) return a+1 end
helpers.benchmark(function()  ta:mapInplace(func) end, bcount, "applyUnary")
assert(ta:eq(bcount+1):all())

ta:assign(1)
tb:assign(1)
local func =  function(a,b, pos) return a+b end
helpers.benchmark(function()  ta:mapBinaryInplace(tb, func) end, bcount, "applyBinary")
assert(ta:eq(bcount+1):all())

ta:assign(1)
tb:assign(1)
tc:assign(1)
local func =  function(a,b,c, pos) return a+b+c end
helpers.benchmark(function()  ta:mapTenaryInplace(tb,tc,func) end, bcount, "applyTenary")
assert(ta:eq(2*bcount+1):all())

helpers.benchmark(function()  ta:assign(0) end, bcount, "assign element")
helpers.benchmark(function()  ta:assign(tb) end, bcount, "assign array")

helpers.benchmark(function()  ta:nonzero() end, 100, "nonzero")

res = ta:nonzero()
helpers.benchmark(function()  ta:setCoordinates(res,0) end, 100, "setCoordinates")

helpers.benchmark(function()  ta:getCoordinates(res) end, 100, "getCoordinates")


