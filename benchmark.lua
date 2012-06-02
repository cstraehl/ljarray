local narray = require("narray")

local bcount = 1000


local ta = narray.create({100,100,100}, narray.int32)
local func =  function(a, pos) return a+1 end
helpers.benchmark(function()  ta:mapInplace(func) end, bcount, "applyUnary")

local ta = narray.create({3,2,1}, narray.int32)
local tb = narray.create({3,2,1}, narray.int32)

ta:assign(1)
ta:print()
tb:assign(2)
tb:print()
ta:add(tb)
ta:print()
local equal = ta:eq(ta)
equal:print()
equal = ta:eq(3)
equal:print()


local view = ta:view({0,1,0},{3,2,1})
view:assign(10)
ta:print()

local lut = narray.create({10}, narray.int32)
lut:assign(1)
lut.data[3] = 7

ta:assign(3)
ta:print()
result = ta:lookup(lut)
result:print()


local index = ta:ravelIndex({1,1,0})
local multiIndex = ta:unravelIndex(index)
io.write(helpers.to_string(multiIndex))

ta = narray.create({100,100,100}, narray.int32)
tb = narray.create({100,100,100}, narray.int32)
tc = narray.create({100,100,100}, narray.int32)

io.write("BEGIN BENCHMARKING\n")
helpers.benchmark(function()  local blubb = narray.create({100,100,100}, narray.int32) end, bcount, "allocate array")
func =  function(a, pos) return a+1 end
helpers.benchmark(function()  ta:mapInplace(func) end, bcount, "applyUnary")

ta:assign(1)
tb:assign(1)
helpers.benchmark(function()  ta:mapInplace(function(a, pos) return a+1 end) end, bcount, "applyUnary")
-- assert(ta:eq(1001):all())

ta:assign(1)
tb:assign(1)
helpers.benchmark(function()  ta:mapBinaryInplace(tb, function(a,b, pos) return a+b end ) end, bcount, "applyBinary")
--ta:view({0,0,0},{10,10,1}):print()
assert(ta:eq(bcount+1):all())

ta:assign(1)
tb:assign(1)
tc:assign(1)
helpers.benchmark(function()  ta:mapTenaryInplace(tb,tc,function(a,b,c, pos) return a+b+c end) end, bcount, "applyTenary")
--ta:view({0,0,0},{10,10,1}):print()
--
assert(ta:eq(2*bcount+1):all())


helpers.benchmark(function()  ta:nonzero() end, 100, "nonzero")

res = ta:nonzero()

helpers.benchmark(function()  ta:setCoordinates(res,0) end, 100, "setCoordinates")

helpers.benchmark(function()  ta:getCoordinates(res) end, 100, "getCoordinates")


