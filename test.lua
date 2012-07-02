local narray = require("narray")

test_shape = {100,20,30}

-- test copy to fortran order
ta = narray.create(test_shape, narray.int32)
tb = ta:copy("f")
assert(tb.order == "f")
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
tb = narray.where(ta, tc, 200)
tb_2 = tb:bind(0,0,50)
assert(tb_2:eq(tc):all())

-- test narray.where number, array
ta = narray.create(test_shape, narray.int32)
tc = narray.create(test_shape, narray.int32)

ta_1 = ta:bind(0,50,100)
ta_2 = ta:bind(0,0,50)

ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, 100, tc)
tb_1 = tb:bind(0,50,100)
assert(tb_1:eq(tc):all())

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
