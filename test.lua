local array = require("array")
local helpers = require("helpers")
local operator = helpers.operator

test_shape = {100,5,6}

-- test copy to fortran order
ta = array.create(test_shape, array.int32)
tb = ta:copy("f")
assert(tb.order == "f")
assert(ta:eq(tb):all())
assert(tb.carray == nil)

-- test copy to c order
ta = array.create(test_shape, array.int32, "f")
tb = ta:copy("c")
assert(tb.order == "c")
assert(ta:eq(tb):all())
assert(tb.carray ~= nil)

-- test .carray property
ta = array.zeros(test_shape, array.int32, "c")
ta:set(7,3,4,11)
assert(ta.carray[7][3][4] == 11, ta.carray[7][3][4])
ta.carray[11][2][3] = 4
assert(ta:get(11,2,3) == 4, ta:get(11,2,3))
ta:assign(0)
tb = ta:bind(1,1,3)
tb:set(7,2,4,11)
assert(tb.carray[7][2][4] == 11, tb.carray[7][2][4])
assert(ta.carray[7][3][4] == 11, ta.carray[7][3][4])

ta = array.zeros({100,200}, array.int32, "c")
ta:set(7,3,11)
assert(ta.carray[7][3] == 11, ta.carray[7][3])
ta.carray[11][2] = 4
assert(ta:get(11,2) == 4, ta:get(11,2))


-- test copy to same order
ta = array.create(test_shape, array.int32, "f")
tb = ta:copy()
assert(tb.order == "f")
assert(ta:eq(tb):all())

-- test copy to same order
ta = array.create(test_shape, array.int32, "c")
tb = ta:copy()
assert(tb.order == "c")
assert(ta:eq(tb):all())

ta:assign(2)
for pos in ta:coordinates() do
  ta:setPos(pos,0)
end
assert(ta:eq(0):all())

-- test array.coordinates iterator
ta = array.create(test_shape, array.int32)
ta:assign(0)
for pos in ta:pairs() do
    ta:setPos(pos, ta:getPos(pos) + 1)
end
assert(ta:eq(1):all())

-- test array.pairs iterator
ta = array.create(test_shape, array.int32)
ta:assign(0)
for pos, val in ta:pairs() do
    ta:setPos(pos, ta:getPos(pos) + 1)
end
assert(ta:eq(1):all())

-- test array.values iterator
ta = array.create(test_shape, array.int32)
for pos, val in ta:pairs() do
    ta:setPos(pos, 1)
end
local sum = 0
for val in ta:values() do
    assert(val == 1)
    sum = sum + val
end
local should =  helpers.reduce(operator.mul, ta.shape, 1)
assert(sum == should, string.format("%d vs %d", sum,should))


-- test array.where number, number
ta = array.create(test_shape, array.int32)
ta_1 = ta:bind(0,50,100)
ta_2 = ta:bind(0,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = array.where(ta, 100, 200)
tb_2 = tb:bind(0,0,50)
assert(tb_2:eq(100):all())



-- test array.where array, number
ta = array.create(test_shape, array.int32)
tc = array.create(test_shape, array.int32)

ta_1 = ta:bind(0,50,100)
ta_2 = ta:bind(0,0,50)
ta_1:assign(0)
ta_2:assign(1)
assert(ta.shape ~= nil)
tb = array.where(ta, tc, 200)
tb_2 = tb:bind(0,0,50)
tc_2 = tc:bind(0,0,50)
assert(tb_2:eq(tc_2):all())

-- test array.where number, array
ta = array.create(test_shape, array.int32)
tc = array.create(test_shape, array.int32)

ta_1 = ta:bind(0,50,100)
ta_2 = ta:bind(0,0,50)

ta_1:assign(0)
ta_2:assign(1)
tb = array.where(ta, 100, tc)
tb_1 = tb:bind(0,50,100)
tc_1 = tc:bind(0,50,100)
assert(tb_1:eq(tc_1):all())

-- test array all()
ta:assign(1)
ta:set(3,3,3, 0)
assert(not ta:all())
ta:set(3,3,3, 7)
assert(ta:all())

-- test array any()
ta:assign(0)
ta:set(3,3,3, 7)
assert(ta:any())
ta:set(3,3,3, 0)
assert(not ta:any())


-- test array ge()
ta:assign(0)
tb:assign(0)
ta:set(3,3,3, 7)
assert(ta:ge(tb):all())
tb:set(3,3,3, 8)
assert(not ta:ge(tb):all())


-- test array gt()
ta:assign(0)
tb:assign(0)
ta:set(3,3,3, 7)
assert(not ta:gt(tb):all())
ta:assign(1)
assert(ta:gt(tb):all())

-- test array lt()
ta:assign(0)
tb:assign(1)
ta:set(3,3,3, 7)
assert(not ta:lt(tb):all())
ta:assign(0)
assert(ta:lt(tb):all())

-- test array le()
ta:assign(0)
tb:assign(0)
ta:set(3,3,3, 7)
assert(not ta:le(tb):all())
ta:assign(0)
assert(ta:le(tb):all())

-- test array lookup(lut)
ta:assign(0)
ta:set(3,3,3, 1)
assert(ta:get(3,3,3) == 1)
local lut = array.create({10}, array.uint8)
lut:assign(0)
lut:set(1,7)
local result = ta:lookup(lut)
assert(result.dtype == array.uint8)
assert(result:get(3,3,3) == 7)
result:set(3,3,3,0)
assert(result:eq(0):all())



-- test array lookup(lut) multidimensional
ta:assign(0)
for v in ta:values() do
    assert(v == 0)
end
ta:set(3,3,3, 1)
local lut = array.zeros({10,5}, array.int32)
lut:set(1,3,7)
local result = ta:lookup(lut)
assert(result.ndim == 4)
assert(result:get(3,3,3,3) == 7)
result:set(3,3,3,3,0)
assert(result:eq(0):all())

-- test array.concatenate
ta = array.create({10,20}, array.int32)
tb = array.create({20,20}, array.int32)
ta:assign(0)
tb:assign(1)
local result = array.concatenate({ta,tb},0)
assert(result.shape[0] == 30)
assert(result:sum() == 20*20)
assert(result:bind(0,0,10):eq(0):all())
assert(result:bind(0,10,30):eq(1):all())

-- test array arange
local t = array.arange(7,11,2)
local i = 0
for v =  7,10,2 do
  assert(t.data[i] == v)
  i = i + 1
end
-- test array arange, only stop
local t = array.arange(7)
local i = 0
for v = 0,6,1 do
  assert(t.data[i] == v)
  i = i + 1
end


-- test array rand
local t = array.rand({10,20})
assert(t.shape[0] == 10)
assert(t.shape[1] == 20)

-- test array randint
local t = array.randint(17,333,{100,200})
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


-- test array sort integer
local t = array.randint(4,10000,{1000})
t:sort()
for i=0,t.shape[0]-2 do
  assert(t.data[i] <= t.data[i+1], "sorting failed at index " .. i .. ":" .. t.data[i] .." is not <= " .. t.data[i+1])
end

-- test array sort float
local t = array.rand({1000})
t:sort()
for i=0,t.shape[0]-2 do
  assert(t.data[i] <= t.data[i+1], "sorting failed at index " .. i .. ":" .. t.data[i] .." is not <= " .. t.data[i+1])
end

-- test array sort float
local t = array.rand({1000})
t:sort(nil,nil,100,200)
for i=100,200-2 do
  assert(t.data[i] <= t.data[i+1], "sorting failed at index " .. i .. ":" .. t.data[i] .." is not <= " .. t.data[i+1])
end


-- test array sort
local t = array.randint(4,10000,{10,100,10})
t:sort()
local v = t:view({0,0,0},{10,1,10})
for pos in v:coordinates() do
  for i = 0, t.shape[1]-2 do
    assert(t:get(pos[0],i,pos[2]) <= t:get(pos[0],i,pos[2]), "sorting failed at position " .. helpers.to_string(pos) .. ":" .. t:get(pos[0],i,pos[2]) .." is not <= " .. t:get(pos[0],i+1,pos[2]))
  end
end

-- test array argsort
local t = array.rand({100})
t.data[77] = 99999 -- watermark t before argsort
local coordinates = t:argsort(nil,nil,10,90)
assert(t.data[77] == 99999) -- test t is still unssorted
t = t:getCoordinates(coordinates)
for i=10,90-2 do
  assert(t.data[i] <= t.data[i+1], "sorting failed at index " .. i .. ":" .. t.data[i] .." is not <= " .. t.data[i+1])
end



-- test max
local t = array.create({100,200})
t:assign(100)
t:set(10,10,200)
local r = t:max()
assert(r == 200, r)

-- test min
t:set(10,10,0)
local r = t:min()
assert(r == 0)


-- test  shift
local t = array.arange(0,10)
t:shift(-1)
assert(t:get(0) == 1)
assert(t:get(9) == 0)
t:shift(2)
assert(t:get(0) == 9)
assert(t:get(9) == 8)

-- test histogram
local t = array.arange(0,10)
local h = t:histogram()
assert(h.shape[0] == 10)
assert(h:eq(1):all())
t.data[9] = 0
local h = t:histogram()
assert(h.data[0] == 2)


-- test clip
local t = array.rand({100,100,100})
t:clip(0.4,0.6)
assert(t:le(0.6):all())
assert(t:ge(0.4):all())
