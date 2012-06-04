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

local Array = {}
Array.__index = Array

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local load_success,helpers = pcall(require,"helpers")
if not load_success then
  helpers = require("ljarray.helpers")
end

-- throw errors on global variable declaration
local _helpers_forbid_globals_backup = helpers.__FORBID_GLOBALS
helpers.__FORBID_GLOBALS = true


local isnarray = function(a)
  if type(a) == "table" and (a.__metatable == Array or a._type == "narray") then
    return true
  else
    return false
  end
end

-- some VLA ffi types for arrays
Array.element_type = {}

Array.int8 = ffi.typeof("char[?]");
Array.element_type[Array.int8] = ffi.typeof("char")

Array.int32 = ffi.typeof("int[?]");
Array.element_type[Array.int32] = ffi.typeof("int")

Array.int64 = ffi.typeof("long[?]");
Array.element_type[Array.int64] = ffi.typeof("long")

Array.uint8 = ffi.typeof("unsigned char[?]");
Array.element_type[Array.uint8] = ffi.typeof("unsigned char")

Array.uint32 = ffi.typeof("unsigned int[?]");
Array.element_type[Array.uint32] = ffi.typeof("unsigned int")

Array.uint64 = ffi.typeof("unsigned long[?]");
Array.element_type[Array.uint64] = ffi.typeof("unsigned long")

Array.float32 = ffi.typeof("float[?]");
Array.element_type[Array.float32] = ffi.typeof("float")

Array.float64 = ffi.typeof("double[?]");
Array.element_type[Array.float64] = ffi.typeof("double")

Array.pointer = ffi.typeof("void *");
Array.element_type[Array.pointer] = ffi.typeof("void *")
 


local operator = {
     mod = math.mod;
     pow = math.pow;
     add = function(n,m) return n + m end;
     sub = function(n,m) return n - m end;
     mul = function(n,m) return n * m end;
     div = function(n,m) return n / m end;
     gt  = function(n,m) return n > m end;
     lt  = function(n,m) return n < m end;
     eq  = function(n,m) return n == m end;
     le  = function(n,m) return n <= m end;
     ge  = function(n,m) return n >= m end;
     ne  = function(n,m) return n ~= m end;
     assign  = function(a,b) return b end; 
 }

-- helper method that specializes some critical functions depending
-- on the number of dimensions of the array
function Array.fixMethodsDim(self)
  self.ndim = #self.shape
  if self.ndim == 1 then
    self.get = Array.get1
    self.getPos = Array.getPos1
    self.set = Array.set1
    self.setPos = Array.setPos1
  elseif self.ndim == 2 then
    self.get = Array.get2
    self.getPos = Array.getPos2
    self.set = Array.set2
    self.setPos = Array.setPos2
  elseif self.ndim == 3 then
    self.get = Array.get3
    self.getPos = Array.getPos3
    self.set = Array.set3
    self.setPos = Array.setPos3
  elseif self.ndim == 4 then
    self.get = Array.get4
    self.getPos = Array.getPos4
    self.set = Array.setN
    self.setPos = Array.setPos4
  else
    -- TODO: these methods are SLOOOW!
    self.get = self.getN
    self.getPos = self.getPosN
    self.set = Array.set1
    self.setPos = Array.setPosN
  end
end

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
  if type(strides) == "table" then
    array.strides = strides
    if #strides == 1 then
      array.order = "c" -- default is c order
    else
      if strides[2] > strides[1] then
        array.order = "f"
      else
        array.order = "c"
      end
    end
  elseif strides == "f" then
    array.order = "f"
    array.strides = {} 
    array.strides[1] = 1
    for i = 2,#shape,1 do
      array.strides[i] = shape[i-1] * array.strides[i-1]
    end
  elseif strides == "c" or not strides then
    array.order = "c"
    array.strides = {} 
    array.strides[#shape] = 1
    for i = #shape-1,1,-1 do
      array.strides[i] = shape[i+1] * array.strides[i+1]
    end
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
   local size = helpers.reduce(operator.mul, shape, 1)

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

function Array.view(self,start, stop)
-- construct a strided view to an subarray of self
-- 
-- required parameters
--  start: start coordinates of view, table of length shape
--  stop : stop coordinates of view, table of length shape
  assert(#start == #stop)
  assert(#start == #self.shape)

  -- calcualte data pointer offset
  local offset = 0
  for i=1,#start,1 do
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
  local data = self.data + self.strides[dimension]*(start)
  local shape = {}
  local strides = {}
  if not stop then
    for i=1,dimension,1 do
      array.strides[i] = self.strides[i]
      array.shape[i] = self.shape[i]
    end
    for i=dimension+1,#self.shape,1 do
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

function Array.mapInplace(self,f, call_with_position)
-- iterates over an array and calls a function for each value
--
-- required
--  f       : function to call. the function receives the
--            value of the array element as first argument
--            and optionally table with the coordinate of
--            the current element
--            the return value of the function for each
--            element is stored in the array.
-- optional
--  call_with_position : if true, the funciton f will be
--            called with the currents array element position
    local temp, offset, i
    local pos = helpers.binmap(operator.sub, self.shape, self.shape)
    local ndim = self.ndim
    local d = 1
    local offseta = 0
    while pos[1] < self.shape[1] do
      -- print(helpers.to_string(pos), d)
      if d == ndim then
        -- iterate over array
        local stride = self.strides[d]
        local stop = (self.shape[d]-1 )*stride
        pos[ndim] = 0
        if call_with_position ~= true then
          for offset=0,stop,stride do
            self.data[offseta + offset] = f(self.data[offseta + offset])
          end
        else
          for offset=0,stop,stride do
            self.data[offseta + offset] = f(self.data[offseta + offset], pos)
            pos[ndim] = pos[ndim] + 1
          end
        end
        pos[ndim] = self.shape[d]
        offseta = offseta + self.shape[d]*(self.strides[d])
      end
      if ((pos[d] == self.shape[d])and(d ~= 1)) then
        pos[d] = 0
        offseta = offseta - self.strides[d]*(self.shape[d])

        d = d - 1
        pos[d] = pos[d] + 1
        offseta = offseta + self.strides[d]
      else
        d = d + 1
      end
      -- print("blubb1")
    end
  end

function Array.mapBinaryInplace(self,other,f, call_with_position)
-- iterates jointly over two arrays and calls a function with
-- the two values of the arrays at the current coordinate
--
-- required
--  other   : the other array, must have the same dimension and shape
--  f       : function to call. the function receives the
--            value of the array element as first argument
--            and the value of the second arrays as second arguemnt.
--            third argument is optionally a table with the coordinate of
--            the current elements.
--            The return value of f for each element pair
--            is stored in the first array.
-- optional
--  call_with_position : if true, the funciton f will be
--            called with the currents array element position
  local temp_a, temp_b, offset_a, offset_b, i
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 1
  local base_offset_a = 0
  local base_offset_b = 0

  while pos[1] < self.shape[1] do
    -- print(helpers.to_string(pos), d)
    if d == ndim then
      -- iterate over array
      local stride_a = self.strides[d]
      local stride_b = other.strides[d]
      offset_b = 0

      local stop = (self.shape[d]-1 ) *stride_a
      pos[d] = 0
      for offset_a=0,stop,stride_a do
        temp_a = self.data[base_offset_a + offset_a]
        temp_b = other.data[base_offset_b + offset_b] 
        
        if call_with_position ~= true then
          self.data[base_offset_a + offset_a] = f(temp_a, temp_b)
        else
          self.data[base_offset_a + offset_a] = f(temp_a, temp_b, pos)
          pos[d] = pos[d] + 1
        end

        offset_b = offset_b + stride_b
      end

      pos[d] = self.shape[d]
      base_offset_a = base_offset_a + self.shape[d]*(self.strides[d])
      base_offset_b = base_offset_b + other.shape[d]*(other.strides[d])
    end
    if ((pos[d] == self.shape[d])and(d ~= 1)) then
      pos[d] = 0
      base_offset_a = base_offset_a - self.strides[d]*(self.shape[d])
      base_offset_b = base_offset_b - other.strides[d]*(other.shape[d])

      d = d - 1
      pos[d] = pos[d] + 1
      base_offset_a = base_offset_a + self.strides[d]
      base_offset_b = base_offset_b + other.strides[d]
    else
      d = d + 1
    end
  end
end

function Array.mapTenaryInplace(self,other_b, other_c,f, call_with_position)
-- iterates jointly over three arrays and calls a function with
-- the three values of the arrays at the current coordinate
--
-- required
--  other_b   : the second array, must have the same dimension and shape
--  other_c   : the third array, must have the same dimension and shape
--  f       : function to call. the function receives the
--            value of the array element as first argument
--            and the value of the second arrays as second arguemnt
--            and the value of the third array as third argument.
--            third argument is optionally a table with the coordinate of
--            the current elements.
--            The return value of f for each element triple is stored
--            in the first array.
-- optional
--  call_with_position : if true, the funciton f will be
--            called with the currents array element position
  local temp_a, temp_b, temp_c, offset_a, offset_b, offset_c, i
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = #self.shape
  local d = 1
  local base_offset_a = 0
  local base_offset_b = 0
  local base_offset_c = 0

  while pos[1] < self.shape[1] do
    -- print(helpers.to_string(pos), d)
    if d == ndim then
      -- iterate over array
      local stride_a = self.strides[d]
      local stride_b = other_b.strides[d]
      local stride_c = other_c.strides[d]

      offset_b = 0
      offset_c = 0

      local stop = (self.shape[d]-1 ) *stride_a
      pos[ndim] = 0

      for offset_a=0,stop,stride_a do
        temp_a = self.data[base_offset_a + offset_a]
        temp_b = other_b.data[base_offset_b + offset_b]
        temp_c = other_c.data[base_offset_c + offset_c]
        
        if call_with_position ~= true then
          self.data[base_offset_a + offset_a] = f(temp_a, temp_b, temp_c)
        else
          self.data[base_offset_a + offset_a] = f(temp_a, temp_b, temp_c, pos)
          pos[ndim] = pos[ndim] + 1
        end

        self.data[base_offset_a + offset_a] = f(temp_a, temp_b, temp_c)
        offset_b = offset_b + stride_b
        offset_c = offset_c + stride_c
      end

      pos[d] = self.shape[d]
      base_offset_a = base_offset_a + self.shape[d]*(self.strides[d])
      base_offset_b = base_offset_b + other_b.shape[d]*(other_b.strides[d])
      base_offset_c = base_offset_c + other_c.shape[d]*(other_c.strides[d])
    end
    if ((pos[d] == self.shape[d])and(d ~= 1)) then
      pos[d] = 0
      base_offset_a = base_offset_a - self.strides[d]*(self.shape[d])
      base_offset_b = base_offset_b - other_b.strides[d]*(other_b.shape[d])
      base_offset_c = base_offset_c - other_c.strides[d]*(other_c.shape[d])

      d = d - 1
      pos[d] = pos[d] + 1
      base_offset_a = base_offset_a + self.strides[d]
      base_offset_b = base_offset_b + other_b.strides[d]
      base_offset_c = base_offset_c + other_c.strides[d]
    else
      d = d + 1
    end
  end
end

function Array.mapCoordinates(self,coord, f)
-- calls a function f for some coordinates
--
-- required
--  coord   : table of coordinates, the length of the table
--            must equal the dimension of the array
--            the table elements must be arrays of type int32
--            which hold valid array coordinate indices
--            for the corresponding dimension.
--  f       : the function to be called.
--            first argument is the value of the array at the current
--            coordinate.
--            second argument is the current joint index inthe
--            coordinate table arrays.
--            The return value of f for each coordinate is stored
--            in the array.
  assert(#coord == #self.shape)

  local temp, offset, i
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 1
  
  -- precalculate offsets to prevent a small inner loop
  local offsets = Array.create(coord[1].shape, Array.int32)
  for i=0,coord[1].shape[1]-1,1 do
    offsets.data[i] = self.strides[1]*coord[1]:get1(i)
  end
  for j=2,ndim,1 do
    for i=0,coord[1].shape[1]-1,1 do
      offsets.data[i] = offsets.data[i] + self.strides[j]*coord[j]:get1(i)
    end
  end

  -- apply the function
  for i=0,coord[1].shape[1]-1,1 do
    self.data[offsets.data[i]] = f(self.data[offsets.data[i]], i)
  end
end


local _set_coord_data
local _set_coord1 = function(a, index)
  return _set_coord_data:get1(index)
end
local _set_coord2 = function(a, index)
  return _set_coord_data
end

function Array.setCoordinates(self,coord, data)
-- set array values for some coordinates
--
-- required
--  coord   : table of coordinate indices in the correspoinding dimension
--            length of coord table must equal array dimensionality
--  data    : either a constant single array alement or
--            an array of elements whose length euquals the number
--            of coordinates
--
  _set_coord_data = data
  if isnarray(data) then
    assert(#data.shape == 1)
    -- map over the coord array
    self:mapCoordinates(coord, _set_coord1)
  else
    -- map over the coord array
    self:mapCoordinates(coord, _set_coord2)
  end
end


local _get_coord_result
local _get_coord_update_values = function(a, index)
  _get_coord_result.data[index] = a
  return a
end

function Array.getCoordinates(self,indices)
-- get array values for some coordinates
--
-- required
--  coord   : table of coordinate indices in the correspoinding dimension
--            length of coord table must equal array dimensionality
  assert(#indices == self.ndim)
  _get_coord_result = Array.create({indices[1].shape[1]}, self.dtype)
  self:mapCoordinates(indices, _get_coord_update_values)
  return _get_coord_result
end

function Array.where(self, boolarray, a, b)
-- set array values depending on truth of boolarray to a (1) or b (0)
-- can also be used as a static function, i.e. without self
-- in this case the arguments are shifted to the left and the
-- last argument (b) is an optional memory order ("c","f") for
-- the result array.
--
-- required
--  boolarray: array of shape self.shape containt 0 and 1s
--  a  : a single array elemnt or an array of shape self.shape
--  b  : a single array element of an array of shape self.shape
--

  if not b or type(b) == "string" then -- assume static call
    local order = b
    b = a
    a = boolarray
    boolarray = self
    local dtype = Array.float32
    if isnarray(a) then
      dtype = a.dtype
    elseif isnarray(b) then
      dtype = b.dtype
    end
    self = Array.create(boolarray.shape, dtype, order)
  end

  local nz = boolarray:nonzero()
  self:assign(b)
  if isnarray(a) then 
    local values = a:getCoordinates(nz)
    self:setCoordinates(nz,values)
  else -- asume element
    self:setCoordinates(nz,a)
  end
  return self
end


local _assign_constant_value
local _assign_constant = function(x)
  return _assign_constant_value
end

function Array.assign(self,data)
  if isnarray(data) then
    -- asume Array table
    self:mapBinaryInplace(data, operator.assign)
  else
    _assign_constant_value = data
    self:mapInplace( _assign_constant )
  end
end


local _add_constant_value
local _add_constant = function(x)
  return x + _add_constant_value
end

function Array.add(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, operator.add)
  else
    _add_constant_value = other
    self:mapInplace(_add_constant)
  end
end


local _sub_constant_value
local _sub_constant = function(x)
  return x - _sub_constant_value
end

function Array.sub(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, operator.sub)
  else
    _sub_constant_value = other
    self:mapInplace(_sub_constant)
  end
end

local _mul_constant_value
local _mul_constant = function(x)
  return x * _mul_constant_value
end

function Array.mul(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, operator.mul)
  else
    _mul_constant_value = other
    self:mapInplace(_mul_constant)
  end
end


local _div_constant_value
local _div_constant = function(x)
  return x / _div_constant_value
end

function Array.div(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, operator.div)
  else
    _div_constant_value = other
    self:mapInplace(_div_constant)
  end
end


local _eq_constant_value
local _eq_constant = function(a,b)
  if b == _eq_constant_value then
    return 1
  else 
    return 0
  end
end

function Array.eq(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b == c then return 1 else return 0 end end)
  else
    _eq_constant_value = ffi.cast(self.element_type, other)
    result:mapBinaryInplace(self, _eq_constant)
  end
  return result
end


local _neq_constant_value
local _neq_constant = function(a,b)
  if b ~= _neq_constant_value then
    return 1
  else
    return 0
  end
end

function Array.neq(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b == c then return 0 else return 1 end end)
  else
    _neq_constant_value = ffi.cast(self.element_type, other)
    result:mapBinaryInplace(self, _neq_constant)
  end
  return result
end


local _gt_constant_value
local _gt_constant = function(a,b)
  if b > _gt_constant_value then
    return 1
  else
    return 0
  end
end

function Array.gt(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b > c then return 1 else return 0 end end)
  else
    _gt_constant_value = ffi.cast(self.element_type, other)
    result:mapBinaryInplace(self, _gt_constant)
  end
  return result
end


local _ge_constant_value
local _ge_constant = function(a,b)
  if b >= _ge_constant_value then
    return 1
  else
    return 0
  end
end

function Array.ge(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b >= c then return 1 else return 0 end end)
  else
    _ge_constant_value = ffi.cast(self.element_type, other)
    result:mapBinaryInplace(self, _ge_constant)
  end
  return result
end


local _lt_constant_value
local _lt_constant = function(a,b)
  if b < _lt_constant_value then
    return 1
  else
    return 0
  end
end

function Array.lt(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b < c then return 1 else return 0 end end)
  else
    _lt_constant_value = ffi.cast(self.element_type, other)
    result:mapBinaryInplace(self, _lt_constant)
  end
  return result
end


local _le_constant_value
local _le_constant = function(a,b)
  if b <= _re_constant_value then
    return 1
  else
    return 0
  end
end

function Array.le(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b <= c then return 1 else return 0 end end)
  else
    _le_constant_value = ffi.cast(self.element_type, other)
    result:mapBinaryInplace(self, _le_constant)
  end
  return result
end


local _all_result
local _all = function(a)
  if a == 0 then
    _all_result = false
  end
  return a
end

function Array.all(self)
  _all_result = true
  self:mapInplace(_all)
  return _all_result
end


local _any_result
local _any = function(a)
  if a ~= 0 then
    _any_result = true
  end
  return a
end

function Array.any(self)
  _any_result = false
  self:mapInplace(_any)
  return _any_result
end

local _lookup_lut
local _lookup = function(a,b)
  return _lookup_lut.data[b]
end

function Array.lookup(self,lut, order)
-- lookup values in table based on array element values
--
-- required
--  lut : the lookup table to be used
  local result = Array.create(self.shape, lut.dtype, order)
  _lookup_lut = lut
  result:mapBinaryInplace( self, _lookup)
  return result
end


-- closure that inserts the coordinates into the result array
local _nonzero_count = 0
local _nonzero_ndim = 0
local _nonzero_result

local _nonzero_update_indices = function(a,pos)
  if a ~= 0 then
    for i=1,_nonzero_ndim,1 do
      _nonzero_result[i].data[_nonzero_count] = pos[i]
    end
    _nonzero_count = _nonzero_count + 1
  end
  return a
end 

local _nonzero_count_nz = function(a)
  if a ~= 0 then _nonzero_count = _nonzero_count + 1 end
  return a
end


function Array.nonzero(self, order)
-- get coord table of nonzero elements

   -- reset shared upvalues
  _nonzero_count = 0
  _nonzero_ndim = #self.shape

  -- determine number of nonzero elements
  self:mapInplace(_nonzero_count_nz)

  -- allocate arrays for dimension indices
  _nonzero_result = {}
  for i=1,_nonzero_ndim,1 do
    _nonzero_result[i] = Array.create({_nonzero_count},Array.int32, order)
  end

  -- reset count, user for position in result array
  _nonzero_count = 0
  
  self.mapInplace(self,_nonzero_update_indices, true)
  return _nonzero_result
end

--
--
-- Dimensionality-specialized getter and setter functions
--
--

function Array.get1(self,i)
  return self.data[i*self.strides[1]] 
end

function Array.get2(self,i,j)
  return self.data[i*self.strides[1] + j*self.strides[2]] 
end

function Array.get3(self, i,j,k)
  return self.data[i*self.strides[1] + j*self.strides[2] + k*self.strides[3]] 
end

function Array.get4(self,i,j,k,l)
  return self.data[i*self.strides[1] + j*self.strides[2] + k*self.strides[3] + l*self.strides[4]] 
end

function Array.getPos1(self, pos)
  return self:get3(pos[1])
end

function Array.getPos2(self, pos)
  return self:get3(pos[1],pos[2])
end

function Array.getPos3(self, pos)
  return self:get3(pos[1],pos[2],pos[3])
end

function Array.getPos4(self, pos)
  return self:get3(pos[1],pos[2],pos[3], pos[4])
end

function Array.getPosN(self,pos)
  -- TODO:implement
  assert(1==2)
end

function Array.set1(self, i, val)
  self.data[i*self.strides[1]] = val
end

function Array.set2(self, i,j, val)
  self.data[i*self.strides[1] + j*self.strides[2]] = val
end

function Array.set3(self, i,j,k, val)
  self.data[i*self.strides[1] + j*self.strides[2] + k*self.strides[3]] = val
end

function Array.set4(self, i,j,k,l, val)
  self.data[i*self.strides[1] + j*self.strides[2] + k*self.strides[3] + l*self.strides[4]] = val
end

function Array.setN(self,val, ...)
  self:setPosN(...,val)
end

function Array.setPos1(self, pos, val)
  self:set1(pos[1],val)
end

function Array.setPos2(self, pos, val)
  self:set1(pos[1],pos[2],val)
end

function Array.setPos3(self, pos, val)
  self:set1(pos[1],pos[2],pos[3],val)
end

function Array.setPos4(self, pos, val)
  self:set1(pos[1],pos[2],pos[3],pos[4],val)
end

function Array.setPosN(self, pos, val)
  -- TODO: slooow
  local offset = helpers.reduce(operator.add, helpers.binmap(operator.mul, pos, self.strides), 0)
  self.data[offset] = val
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


-- pointer types
local cpointer = {}
cpointer.int8 = ffi.typeof("char*");
cpointer.int32 = ffi.typeof("int*");
cpointer.int64 = ffi.typeof("long*");
cpointer.uint8 = ffi.typeof("unsigned char*");
cpointer.uint32 = ffi.typeof("unsigned int*");
cpointer.uint64 = ffi.typeof("unsigned long*");
cpointer.float32 = ffi.typeof("float*");
cpointer.float64 = ffi.typeof("double*");

function Array.fromNumpyArray(ndarray)
  local dtype = cpointer[tostring(ndarray.dtype)]
  local data = ffi.cast(dtype,ndarray.ctypes.data)
  local shape = {}
  local strides = {}
  local elem_size = ndarray.nbytes / ndarray.size
  for i = 1,ndarray.ndim,1 do
    shape[i] = ndarray.shape[i-1]
    strides[i] = ndarray.strides[i-1] / elem_size
  end
  local array = Array.fromData(data, dtype, shape, strides, ndarray)
  return array
end

-- restore __FORBID_GLOBALS behaviour
helpers.__FORBID_GLOBALS = _helpers_forbid_globals_backup

return Array            
