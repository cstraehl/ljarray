local narray = require("narray")

local bcount = 200

local ta = narray.create({100,100,100}, narray.int32)
local taf = narray.create({100,100,100}, narray.float32)
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

helpers.benchmark(function()  ta:add(tb) end, bcount, "add array")
helpers.benchmark(function()  ta:add(3) end, bcount, "add constant")
helpers.benchmark(function()  ta:sub(tb) end, bcount, "sub array")
helpers.benchmark(function()  ta:sub(1) end, bcount, "sub constant")
helpers.benchmark(function()  ta:eq(tc) end, bcount, "eq(array)")
helpers.benchmark(function()  ta:eq(7) end, bcount, "eq(constant)")
helpers.benchmark(function()  taf:eq(7) end, bcount, "eq(constant) for float array")
helpers.benchmark(function()  ta:neq(tc) end, bcount, "neq(array)")
helpers.benchmark(function()  ta:neq(7) end, bcount, "neq(constant)")
helpers.benchmark(function()  taf:neq(7) end, bcount, "neq(constant) for float array")
helpers.benchmark(function()  ta:all() end, bcount, "all() test array")
helpers.benchmark(function()  ta:any() end, bcount, "any() test array")
helpers.benchmark(function()  ta:assign(0) end, bcount, "assign element")
helpers.benchmark(function()  ta:assign(tb) end, bcount, "assign array")
helpers.benchmark(function()  ta:nonzero() end, bcount, "nonzero")

ta:assign(3)
local lut = narray.create({10}, narray.uint8)
lut:set(0,0)
lut:set(1,10)
lut:set(2,20)
lut:set(3,30)
helpers.benchmark(function()  ta:lookup(lut) end, bcount, "lookup(lut)")

local res = ta:nonzero()
helpers.benchmark(function()  ta:setCoordinates(res,0) end, bcount, "setCoordinates")
helpers.benchmark(function()  ta:getCoordinates(res) end, bcount, "getCoordinates")



