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
ta_1 = ta:bind(1,50,100)
ta_2 = ta:bind(1,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, 100, 200)
tb_2 = tb:bind(1,0,50)
assert(tb_2:eq(100):all())



-- test narray.where array, number
ta = narray.create(test_shape, narray.int32)
tc = narray.create(test_shape, narray.int32)

ta_1 = ta:bind(1,50,100)
ta_2 = ta:bind(1,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, tc, 200)
tb_2 = tb:bind(1,0,50)
assert(tb_2:eq(tc):all())

-- test narray.where number, array
ta = narray.create(test_shape, narray.int32)
tc = narray.create(test_shape, narray.int32)

ta_1 = ta:bind(1,50,100)
ta_2 = ta:bind(1,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, 100, tc)
tb_1 = tb:bind(1,50,100)
assert(tb_1:eq(tc):all())


