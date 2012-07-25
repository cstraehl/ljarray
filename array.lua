--  array.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD
--

-- extend package.path with path of this .lua file:
local filepath = debug.getinfo(1).source:match("@(.*)$") 
local dir = string.gsub(filepath, '/[^/]+$', '') .. "/"
package.path = dir .. "/?.lua;" .. package.path

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator

Array = {}
Array.__index = Array

-- load additional functionality
require("array_base")
require("array_math")
require("array_sort")
require("array_types")



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
  array._type = "array"
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
  array.base_data = source or array.data
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
   
   assert(type(shape) == "table", "array.create: shape must be of type table")
   local size = helpers.reduce(operator.mul, helpers.zerobased(shape), 1)
   dtype = dtype or Array.float32
   local etype = Array.element_type[dtype]

   local data

   -- TODO: luajit cannot compile this data allocation -> leads to slowdowns
   if etype then
      data = ffi.cast(Array.cpointer[etype], ffi.C.malloc(size * Array.element_type_size[etype]))
      ffi.gc(data, ffi.C.free)
   else
     data = dtype(size)
   end
  
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

function Array.rand(shape, dtype)
-- Random values in a given shape.
-- 
-- Create an array of the given shape and propagate it with 
-- random samples from a uniform distribution over [0, 1).
  if dtype == nil then
    dtype = Array.float32
  end
  local array = Array.create(shape, dtype)
  for pos in array:coordinates() do
    array:setPos(pos, math.random())
  end
  return array
end


function Array.randint(low,high,shape, dtype)
-- Return random integers from low (inclusive) to high (exclusive).
-- 
-- Return random integers from the “discrete uniform” distribution in 
-- the “half-open” interval [low, high). If high is None (the default),
-- then results are from [0, low).
  if dtype == nil then
    dtype = Array.int32
  end
  local array = Array.create(shape, dtype)
  for pos in array:coordinates() do
    array:setPos(pos, math.floor(math.random()*(high-0.1 - low) +low))
  end
  return array
end


function Array.arange(start,stop,step,dtype)
-- array.arange([start], stop[, step], dtype=None)
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
    start = start
    stop = stop
    step = 1
    dtype = Array.int32
  elseif dtype == nil then
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
    start = start
    stop = stop
    step = step
    dtype = Array.int32
  end
  local tshape = {}
  tshape[0] = math.floor((stop-start) / step)
  local array = Array.create(tshape,dtype) 
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
  start = helpers.zerobased(start)
  stop = helpers.zerobased(stop)
  assert(#start == #stop, "dimension of start and stop differ ") -- ..#start .." vs ".. #stop)
  assert(#start + 1 == self.ndim)

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
  
  return Array.fromData(data, self.dtype,  shape, strides, self.base_data)
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
--
  assert(dimension ~= nil, "array.bind: dimension is nil")
  assert(start ~= nil, "array.bind: start index is nil")
  assert(dimension < self.ndim, "array.bind: dimension larger then array dimension.")
  assert(self.shape[dimension] >= start, "array.bind: start index larger then shape")
  if stop then
    assert(self.shape[dimension] >= stop)
  assert(start<=stop)
  end
  local data = self.data + self.strides[dimension]*(start)
  local shape = {}
  local strides = {}
  if stop and stop ~= start then
    for i=0,dimension-1,1 do
      strides[i] = self.strides[i]
      shape[i] = self.shape[i]
    end
    for i=dimension,self.ndim-1,1 do
      strides[i] = self.strides[i]
      shape[i] = self.shape[i]
    end
    shape[dimension] = stop - start
  else
    for i=0,dimension-1,1 do
      strides[i] = self.strides[i]
      shape[i] = self.shape[i]
    end
    for i=dimension+1,self.ndim-1,1 do
      strides[i-1] = self.strides[i]
      shape[i-1] = self.shape[i]
    end
  end
  return Array.fromData(data,self.dtype, shape, strides, self.base_data)
end



function Array.fromNumpyArray(ndarray)
-- construct array from numpy.ndarray (as given by lupa a python<->lua bride)
-- the numpy array and the array share the same memory
  local dtype = Array.cpointer[tostring(ndarray.dtype)]
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


Array.__tostring = function(self)
  local result = "Array" .. "(shape = " .. helpers.to_string(self.shape) .. ", stride = ".. helpers.to_string(self.strides) ..  ", dtype = ".. tostring(self.dtype) .. ")"
  return result
end

return Array            
