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
      ["ljarray.array"] = "array.lua",
      ["ljarray.array_types"] = "array_types.lua",
      ["ljarray.array_base"] = "array_base.lua",
      ["ljarray.array_map"] = "array_map.lua",
      ["ljarray.array_iterators"] = "array_iterators.lua",
      ["ljarray.array_math"] = "array_math.lua",
      ["ljarray.array_sort"] = "array_sort.lua",
      ["ljarray.helpers"] = "helpers.lua",
      ["ljarray.benchmark"] = "benchmark.lua",
      ["ljarray.log"] = "log.lua",
   }
}
