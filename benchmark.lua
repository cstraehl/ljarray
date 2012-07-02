local narray = require("narray")

local bcount = 200
local bshape = {100,100,100}
local btype  = narray.int32

local ta = narray.create(bshape, narray.int32)
local taf = narray.create(bshape, narray.float32)
local tb = narray.create(bshape, narray.int32)
local tc = narray.create(bshape, narray.int32)

print("\nBenchmarks for array shape = ".. helpers.to_string(bshape) ..", type = " .. tostring(btype) .. "\n")

helpers.benchmark(function()  local blubb = narray.create(bshape, btype) end, bcount, "allocate array")
helpers.benchmark(function()  ta:add(3) end, bcount, "add constant")
helpers.benchmark(function()  ta:add(tb) end, bcount, "add array")
helpers.benchmark(function()  ta:sub(tb) end, bcount, "sub array")
helpers.benchmark(function()  ta:sub(1) end, bcount, "sub constant")
helpers.benchmark(function()  ta:eq(7) end, bcount, "eq(constant)")
helpers.benchmark(function()  ta:eq(tc) end, bcount, "eq(array)")
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



