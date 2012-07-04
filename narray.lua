--  narray.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD
--
--
--
-- Investigate LUAJIT strangeness:
--
-- 1) luajit seems to specialize to a function only one time
--    calling the function a second time with different arugment
--    types does not seem to trigger a retrace.
--    leads to very different benchmark results depending
--    on order of benchmark execution.
--
--    Trying to force a retrace/new specialization by using closures
--    does not seem to work..
--
--    Ugly Fix: -Omaxtrace=single digit
--    this seems to flush the trace cache often enough to force
--    an agressive respecialization.
--
-- 2) calling a function defined as Array:function(a,b,c) 
--   is slower then calling the same function
--   defined as Array.function(self, ab, c) ??
--
--

Array = {}
Array.__index = Array

-- extend package.path with path of this .lua file:
local filepath = debug.getinfo(1).source:match("@(.*)$") 
local dir = string.gsub(filepath, '/[^/]+$', '') .. "/"
package.path = dir .. "/?.lua;" .. package.path

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator

-- throw errors on global variable declaration
local _helpers_forbid_globals_backup = helpers.__FORBID_GLOBALS
helpers.__FORBID_GLOBALS = true


-- load additional functionality
require("narray_base")
require("narray_math")
require("narray_sort")

-- some VLA ffi types for arrays
Array.element_type = {}

Array.int8 = ffi.typeof("int8_t[?]");
Array.element_type[Array.int8] = ffi.typeof("int8_t")

Array.int32 = ffi.typeof("int32_t[?]");
Array.element_type[Array.int32] = ffi.typeof("int32_t")

Array.int64 = ffi.typeof("int64_t[?]");
Array.element_type[Array.int64] = ffi.typeof("int64_t")

Array.uint8 = ffi.typeof("uint8_t[?]");
Array.element_type[Array.uint8] = ffi.typeof("uint8_t")

Array.uint32 = ffi.typeof("uint32_t[?]");
Array.element_type[Array.uint32] = ffi.typeof("uint32_t")

Array.uint64 = ffi.typeof("uint64_t[?]");
Array.element_type[Array.uint64] = ffi.typeof("uint64_t")

Array.float32 = ffi.typeof("float[?]");
Array.element_type[Array.float32] = ffi.typeof("float")

Array.float64 = ffi.typeof("double[?]");
Array.element_type[Array.float64] = ffi.typeof("double")

Array.pointer = ffi.typeof("void *");
Array.element_type[Array.pointer] = ffi.typeof("void *")

-- pointer types
local cpointer = {}
cpointer.int8 = ffi.typeof("int8_t*");
cpointer.int32 = ffi.typeof("int32_t*");
cpointer.int64 = ffi.typeof("int64_t*");
cpointer.uint8 = ffi.typeof("uint8_t*");
cpointer.uint32 = ffi.typeof("uint32_t*");
cpointer.uint64 = ffi.typeof("uint64_t*");
cpointer.float32 = ffi.typeof("float*");
cpointer.float64 = ffi.typeof("double*");

 

-- create array from existing data pointer
--
-- required
--  ptr : a ffi pointer to the data
--  dtype : the VLA ffi data type
--  shape : a table that contains the size of the dimension
--
-- optional
--  strides : if nil, the ptr data is sumed to be dense C order
--            otherwise a table of strides can be provided or
--            "f" : for dense fortran order strides
--            "c" : for dense c order strides
--  source : an objects whose reference is stored
--           usecase: custom allocators
function Array.fromData(ptr, dtype, shape, strides, source)
  local array = {}
  setmetatable(array,Array)
  array._type = "narray"
  array.data = ptr
  array.memory = tonumber(ffi.cast("int", array.data))  
  array.dtype = dtype
  array.element_type = Array.element_type[dtype]
  array.str_dtype = tostring(array.element_type)
  
  if shape[0] == nil then
    array.ndim = #shape
    local newshape = {}
    -- 1 based shape
    for i = 1, array.ndim, 1 do
      newshape[i-1] = shape[i]
    end
    shape = newshape
  else
    array.ndim = #shape + 1
  end

  if type(strides) == "table" then
    if strides[0] == nil then
      local newstrides = {}
      -- 1 based strides
      for i = 1, array.ndim, 1 do
        newstrides[i-1] = strides[i]
      end
      strides = newstrides
    end
    array.strides = strides
    if array.ndim == 1 then
      array.order = "c" -- default is c order
    else
      if strides[1] > strides[0] then
        array.order = "f"
      else
        array.order = "c"
      end
    assert(#array.strides == #shape)
    end
  elseif strides == "f" then
    array.order = "f"
    array.strides = {} 
    array.strides[0] = 1
    for i = 1,array.ndim-1,1 do
      array.strides[i] = shape[i-1] * array.strides[i-1]
    end
    assert(#array.strides == #shape)
  elseif strides == "c" or not strides then
    array.order = "c"
    local strides = {} 
    strides[array.ndim-1] = 1
    for i = array.ndim-2,0,-1 do
      strides[i] = shape[i+1] * strides[i+1]
    end
    array.strides = strides
    assert(#(array.strides) == #shape)
  end
  array.shape = shape
  if not source then
    array.source = array    
  else
    array.source = source
  end
  -- calculate size (number of elements)
  array.size = helpers.reduce(operator.mul, shape, 1)
  array:fixMethodsDim()

  assert(#array.shape == #array.strides)
  assert(array.shape[0] ~= nil)
  assert(array.strides[0] ~= nil)


  return array
end


function Array.create(shape, dtype, order)
-- allocate uninitialized array from shape and VLA ffi dtype
--
-- required
--  shape : table containing the size of the array dimension
--  dtype : the VLA ffi dtype of the array
-- 
-- optional
--  order : can be either "f" for fortran order or
--          "c" for c order, default is c order
   
   -- allocate data, do not initialize !
   -- the {0} is a trick to prevent zero
   -- filling. 
   -- BEWARE: array is uninitialized 
   local size = helpers.reduce(operator.mul, helpers.zerobased(shape), 1)

   -- NOTE: the {0} initializer prevents the VLA array from being initialized
   local data = dtype(size, {0}) 
   return Array.fromData(data,dtype,shape,order)
end

function Array.zeros(shape,dtype)
-- convenience function to initialize zero filled array
  
  local array = Array.create(shape, dtype)
  array:assign(0)
  return array
end

function Array.copy(self,order)
-- copy an array
--
-- optional
--  order : either "c" or "f" to produce a c or fortran ordered copy

  if not order then
    order = self.order
  end
  local result = Array.create(self.shape, self.dtype, order) 
  result:mapBinaryInplace(self, operator.assign)
  return result
end


function Array.arange(start,stop,step,dtype)
-- narray.arange([start], stop[, step], dtype=None)
-- Return evenly spaced values within a given interval.
-- 
-- Values are generated within the half-open interval [start, stop)
-- (in other words, the interval including start but excluding stop). 
-- 
-- When using a non-integer step, such as 0.1, the results will 
-- often not be consistent. It is better to use linspace for these cases.
  if stop == nil then
    stop = start
    start = 0
    step = 1
    dtype = Array.int32
  elseif step == nil then
    if type(step) == "number" then
      start = start
      stop = stop
      step = step
      dtype = Array.int32
    else -- dtype was given
      start = start
      stop = stop
      dtype = step
      step = 1
    end
  elseif dtype == nil then
    start = start
    stop = stop
    step = step
    dtype = Array.int32
  end
  local array = Array.create({math.floor((stop-start) / step)},dtype) 
  local i = 0
  for v = start, stop-1,step do
    array.data[i] = v
    i = i + 1
  end
  return array
end

function Array.view(self,start, stop)
-- construct a strided view to an subarray of self
-- 
-- required parameters
--  start: start coordinates of view, table of length shape
--  stop : stop coordinates of view, table of length shape
  assert(#start == #stop)
  assert(#start == self.ndim)

  if start[0] == nil then
    newstart = {}
    newstop = {}
    for i=0,self.ndim-1,1 do
      newstart[i] = start[i+1]
      newstop[i] = stop[i+1]
    end
    start = newstart
    stop = newstop
  end


  -- calcualte data pointer offset
  local offset = 0
  for i=0,self.ndim-1,1 do
    offset = offset + start[i] * self.strides[i]
  end
  local data = self.data + offset

  -- calculate shape
  local shape = helpers.binmap(operator.sub, stop, start)

  -- calculate strides
  local strides = self.strides
  
  return Array.fromData(data, self.dtype,  shape, strides, self)
end

function Array.bind(self,dimension, start, stop)
-- constructs a strided view of an axis
--
-- required 
--  dimension: dimension
--  start    : start index in dimension
--
-- optional
--  stop     : stop index in dimension (exclusive)
--
-- if no stop index is given the ndim of the returned
-- view is self.ndim-1
  assert(self.shape[dimension] >= stop)
  assert(self.shape[dimension] >= start)
  assert(start<=stop)
  local data = self.data + self.strides[dimension]*(start)
  local shape = {}
  local strides = {}
  if not stop or stop == start then
    for i=0,dimension-1,1 do
      array.strides[i] = self.strides[i]
      array.shape[i] = self.shape[i]
    end
    for i=dimension,self.ndim-1,1 do
      array.strides[i-1] = self.strides[i]
      array.shape[i-1] = self.shape[i]
    end
  else
    shape = helpers.copy(self.shape)
    shape[dimension] = stop - start
    strides = self.strides
  end

  return Array.fromData(data,self.dtype, shape, strides, self)
end



function Array.fromNumpyArray(ndarray)
-- construct narray from numpy.ndarray (as given by lupa a python<->lua bride)
-- the numpy array and the narray share the same memory
  local dtype = cpointer[tostring(ndarray.dtype)]
  local data = ffi.cast(dtype,ndarray.ctypes.data)
  local shape = {}
  local strides = {}
  local elem_size = ndarray.nbytes / ndarray.size
  for i = 0,ndarray.ndim-1,1 do
    shape[i] = ndarray.shape[i]
    strides[i] = ndarray.strides[i] / elem_size
  end
  local array = Array.fromData(data, dtype, shape, strides, ndarray)
  return array
end


local _print_element = function(x)
  io.write(x, " ")
  return x
end

function Array.print(self)
  self:mapInplace( _print_element)
  io.write("\nArray", tostring(self), "(shape = ", helpers.to_string(self.shape))
  io.write(", stride = ", helpers.to_string(self.strides))
  io.write(", dtype = ", tostring(self.dtype), ")\n")
end

Array.__tostring = function(self)
  local result = "\nArray" .. "(shape = " .. helpers.to_string(self.shape) .. ", stride = ".. helpers.to_string(self.strides) ..  ", dtype = ".. tostring(self.dtype) .. ")\n"
  return result
end

-- restore __FORBID_GLOBALS behaviour
helpers.__FORBID_GLOBALS = _helpers_forbid_globals_backup

return Array            
