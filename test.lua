local narray = require("array")

test_shape = {100,3,6}

-- test copy to fortran order
ta = narray.create(test_shape, narray.int32)
tb = ta:copy("c")
assert(tb.order == "c")
assert(ta:eq(tb):all())

-- test copy to c order
ta = narray.create(test_shape, narray.int32, "f")
tb = ta:copy("c")
assert(tb.order == "c")
assert(ta:eq(tb):all())

-- test copy to same order
ta = narray.create(test_shape, narray.int32, "f")
tb = ta:copy()
assert(tb.order == "f")
assert(ta:eq(tb):all())

-- test copy to same order
ta = narray.create(test_shape, narray.int32, "c")
tb = ta:copy()
assert(tb.order == "c")
assert(ta:eq(tb):all())

ta:assign(2)
for pos in ta:coordinates() do
  ta:setPos(pos,0)
end
assert(ta:eq(0):all())

-- test narray.where number, number
ta = narray.create(test_shape, narray.int32)
ta_1 = ta:bind(0,50,100)
ta_2 = ta:bind(0,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, 100, 200)
tb_2 = tb:bind(0,0,50)
assert(tb_2:eq(100):all())



-- test narray.where array, number
ta = narray.create(test_shape, narray.int32)
tc = narray.create(test_shape, narray.int32)

ta_1 = ta:bind(0,50,100)
ta_2 = ta:bind(0,0,50)
ta_1:assign(0)
ta_2:assign(1)
assert(ta.shape ~= nil)
tb = narray.where(ta, tc, 200)
tb_2 = tb:bind(0,0,50)
tc_2 = tc:bind(0,0,50)
assert(tb_2:eq(tc_2):all())

-- test narray.where number, array
ta = narray.create(test_shape, narray.int32)
tc = narray.create(test_shape, narray.int32)

ta_1 = ta:bind(0,50,100)
ta_2 = ta:bind(0,0,50)

ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, 100, tc)
tb_1 = tb:bind(0,50,100)
tc_1 = tc:bind(0,50,100)
assert(tb_1:eq(tc_1):all())

-- test narray all()
ta:assign(1)
ta:set(3,3,3, 0)
assert(not ta:all())
ta:set(3,3,3, 7)
assert(ta:all())

-- test narray any()
ta:assign(0)
ta:set(3,3,3, 7)
assert(ta:any())
ta:set(3,3,3, 0)
assert(not ta:any())


-- test narray ge()
ta:assign(0)
tb:assign(0)
ta:set(3,3,3, 7)
assert(ta:ge(tb):all())
tb:set(3,3,3, 8)
assert(not ta:ge(tb):all())


-- test narray gt()
ta:assign(0)
tb:assign(0)
ta:set(3,3,3, 7)
assert(not ta:gt(tb):all())
ta:assign(1)
assert(ta:gt(tb):all())

-- test narray lt()
ta:assign(0)
tb:assign(1)
ta:set(3,3,3, 7)
assert(not ta:lt(tb):all())
ta:assign(0)
assert(ta:lt(tb):all())

-- test narray le()
ta:assign(0)
tb:assign(0)
ta:set(3,3,3, 7)
assert(not ta:le(tb):all())
ta:assign(0)
assert(ta:le(tb):all())

-- test narray lookup(lut)
ta:assign(0)
ta:set(3,3,3, 1)
local lut = narray.create({10}, narray.uint8)
lut:set(0,0)
lut:set(1,1)
local result = ta:lookup(lut)
assert(result:get(3,3,3) == 1)
result:set(3,3,3,0)
assert(result:eq(0):all())


-- test narray arange
local t = narray.arange(7,11,2)
local i = 0
for v =  7,10,2 do
  assert(t.data[i] == v)
  i = i + 1
end
-- test narray arange, only stop
local t = narray.arange(7)
local i = 0
for v = 0,6,1 do
  assert(t.data[i] == v)
  i = i + 1
end


-- test narray rand
local t = narray.rand({10,20})
assert(t.shape[0] == 10)
assert(t.shape[1] == 20)

-- test narray randint
local t = narray.randint(17,333,{100,200})
assert(t.shape[0] == 100)
assert(t.shape[1] == 200)
assert(t:ge(17):all())
assert(t:lt(333):all())

log = require("log")

log.indent("TEST")
log.log("warning", "%d - hallo %f\n", 100, 1.0)
log.log("error", "Akradabra error %d - hallo %f\n", 100, 1.0)
log.log("error", "zweiter fehler error %d - hallo %f\n", 100, 1.0)
local info = log.unindent()
log.print_runtime(info)


-- test narray sort
local t = narray.randint(4,10000,{1000})
t:sort()
for i=0,t.shape[0]-2 do
  assert(t.data[i] <= t.data[i+1], "sorting failed at index " .. i .. ":" .. t.data[i] .." is not <= " .. t.data[i+1])
end


-- test narray sort
local t = narray.randint(4,10000,{10,100,10})
t:sort()
local v = t:view({0,0,0},{10,1,10})
for pos in v:coordinates() do
  for i = 0, t.shape[1]-2 do
    assert(t:get(pos[0],i,pos[2]) <= t:get(pos[0],i,pos[2]), "sorting failed at position " .. helpers.to_string(pos) .. ":" .. t:get(pos[0],i,pos[2]) .." is not <= " .. t:get(pos[0],i+1,pos[2]))
  end
end

-- test narray argsort
local t = narray.randint(4,10000,{100})
t.data[77] = 99999 -- watermark t before argsort
local coordinates = t:argsort()
assert(t.data[77] == 99999) -- test t is still unssorted
t = t:getCoordinates(coordinates)
for i=0,t.shape[0]-2 do
  assert(t.data[i] <= t.data[i+1], "sorting failed at index " .. i .. ":" .. t.data[i] .." is not <= " .. t.data[i+1])
end
