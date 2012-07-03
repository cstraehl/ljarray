package = "ljarray"
version = "0.1-3"

source = {
   url = "https://github.com/cstraehl/ljarray"
}

description = {
   summary = "An experimental n-dimensional native array library for luajit",
   detailed = [[
      This is a very experimental n-dimensional array library for
      luajit's foreign function interface.
   ]],
   homepage = "https://github.com/cstraehl/ljarray",
   license = "BSD" 
}

dependencies = {
}

build = {
   type = "builtin",
   modules = {
      ["ljarray.narray"] = "narray.lua",
      ["ljarray.narray_base"] = "narray_base.lua",
      ["ljarray.narray_math"] = "narray_math.lua",
      ["ljarray.helpers"] = "helpers.lua",
      ["ljarray.benchmark"] = "benchmark.lua",
   }
}
