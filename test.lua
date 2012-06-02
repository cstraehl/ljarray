local narray = require("narray")


-- test narray.where number, number
ta = narray.create({100,100,100}, narray.int32)
ta_1 = ta:bind(1,50,100)
ta_2 = ta:bind(1,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, 100, 200)
tb_2 = tb:bind(1,0,50)
assert(tb_2:eq(100):all())



-- test narray.where array, number
ta = narray.create({100,100,100}, narray.int32)
tc = narray.create({100,100,100}, narray.int32)

ta_1 = ta:bind(1,50,100)
ta_2 = ta:bind(1,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, tc, 200)
tb_2 = tb:bind(1,0,50)
assert(tb_2:eq(tc):all())

-- test narray.where number, array
ta = narray.create({100,100,100}, narray.int32)
tc = narray.create({100,100,100}, narray.int32)

ta_1 = ta:bind(1,50,100)
ta_2 = ta:bind(1,0,50)
ta_1:assign(0)
ta_2:assign(1)
tb = narray.where(ta, 100, tc)
tb_1 = tb:bind(1,50,100)
assert(tb_1:eq(tc):all())


