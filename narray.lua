--  narray.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD
--
--
--
-- Investigate LUAJIT strangeness:
--
--   calling a function defined as Array:function(a,b,c) 
--   is slower then calling the same function
--   defined as Array.function(self, ab, c) ??
--
--
local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers") 

local Array = {}
Array.__index = Array

local isnarray = function(a)
  if type(a) == "table" and (a. __metatable == Array or a._type == "narray") then
    return true
  else
    return false
  end
end

-- some VLA ffi types for arrays
Array.int8 = ffi.typeof("char[?]");
Array.int32 = ffi.typeof("int[?]");
Array.int64 = ffi.typeof("long[?]");
Array.uint8 = ffi.typeof("unsigned char[?]");
Array.uint32 = ffi.typeof("unsigned int[?]");
Array.uint64 = ffi.typeof("unsigned long[?]");
Array.float32 = ffi.typeof("float[?]");
Array.float64 = ffi.typeof("double[?]");
 


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
  array.dtype = dtype
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
   local data = dtype(size, {0})

   return Array.fromData(data,dtype,shape,order)
end

function Array.zeros(shape,dtype)
-- convenience function to fill initialize zero filled array
  
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
-- construct a strided view to an array
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

function Array.ravelIndex(self,indices)
  local result = helpers.reduce(operator.add, helpers.binmap(operator.mul, indices, helpers.cumreduce(operator.mul, helpers.reverse(self.shape), 1)), 0)
  return result
end

function Array.unravelIndex(self,index)
  local indices = {}
  local temp = helpers.cumreduce(operator.mul, helpers.reverse(self.shape), 1)
  for i=1,#temp,1 do
    local v = temp[i]
    indices[i] = math.floor(index / v)
    if indices[i] == self.shape[i] then
      indices[i] = indices[i] - 1
    end
    index = index - indices[i] * v
  end
  return indices
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
  local fct = other.get3
  local fct2 = other.get

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
        --temp_b = other:get3(pos[1],pos[2],pos[3])--
        --temp_b = other.data[pos[1]*other.strides[1] + pos[2]*other.strides[2] + pos[3]*other.strides[3]]
        --temp_b = get3(other,pos[1],pos[2],pos[3])
        -- temp_b = fct(other,pos[1],pos[2],pos[3])
        -- temp_b = fct2(other,pos)
        -- temp_b = other:getPos(pos)
        
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
    -- print("blubb2")
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
    -- print("blubb3")
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

function Array.setCoordinates(self,coord, data)
-- set array value for some coordinates
--
-- required
--  coord   : table of coordinate indices in the correspoinding dimension
--            length of coord table must equal array dimensionality
--  data    : either a constant single array alement or
--            an array of elements whose length euquals the number
--            of coordinates
--
  local update_values
  if isnarray(data) then
    assert(#data.shape == 1)
    update_values = function(a, coord_index)
      return data:get1(coord_index)
    end
  else
    update_values = function(a, coord_index)
      return data
    end
  end
  -- map over the coord array
  self:mapCoordinates(coord, update_values)
end


function Array.getCoordinates(self,indices)
-- get array values for some coordinates
--
-- required
--  coord   : table of coordinate indices in the correspoinding dimension
--            length of coord table must equal array dimensionality
  assert(#indices == self.ndim)
  local result = Array.create({indices[1].shape[1]}, self.dtype)
  local update_values = function(a, index)
    result.data[index] = a -- the new array has no strides
    return a
  end
  self:mapCoordinates(indices, update_values)
  return result
end

function Array.where(self, boolarray, a, b, order)
-- set array values depending on truth of boolarray to a (1) or b (0)
-- can also be used as a static function, i.e. without self
-- in this case the arguments are shifted to the left
--
-- required
--  boolarray: array of shape self.shape containt 0 and 1s
--  a  : a single array elemnt or an array of shape self.shape
--  b  : a single array element of an array of shape self.shape
--

  if not b then -- assume static call
    b = a
    a = boolarray
    boolarray = self
    local dtype = Array.float32
    if isnarray(a) then
      dtype = a.dtype
    elseif isnarray(b) then
      dtype = b.dtype
    else
      error("narray.where: first or second argument must be of type narray")
    end
    self = Array.create(boolarray.shape, dtype)
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

function Array.assign(self,data)
  if isnarray(data) then
    -- asume Array table
    self:mapBinaryInplace(data, function(a,b) return b end)
  else
    self:mapInplace( function(x) return data end )
  end
end

function Array.add(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, function(a,b) return a+b end)
  else
    self:mapInplace(function(a) return a + other end)
  end
end

function Array.sub(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, function(a,b) return a-b end)
  else
    self:mapInplace(function(a) return a - other end)
  end
end

function Array.mul(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, function(a,b) return a*b end)
  else
    self:mapInplace(function(a) return a * other end)
  end
end

function Array.div(self,other)
  if isnarray(other) then
    -- asume Array table
    self:mapBinaryInplace(other, function(a,b) return a / b end)
  else
    self:mapInplace(function(a) return a / other end)
  end
end

function Array.eq(self,other)
  local result = Array.create(self.shape, Array.int8)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b == c then return 1 else return 0 end end)
  else
    result:mapBinaryInplace(self, function(a,b) if b == other then return 1 else return 0 end end)
  end
  return result
end

function Array.neq(self,other)
  local result = Array.create(self.shape, Array.int8)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b == c then return 0 else return 1 end end)
  else
    result:mapBinaryInplace(self, function(a,b) if b == other then return 0 else return 1 end end)
  end
  return result
end

function Array.gt(self,other)
  local result = Array.create(self.shape, Array.int8)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b > c then return 1 else return 0 end end)
  else
    result:mapBinaryInplace(self, function(a,b) if b > other then return 1 else return 0 end end)
  end
  return result
end

function Array.ge(self,other)
  local result = Array.create(self.shape, Array.int8)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b >= c then return 1 else return 0 end end)
  else
    result:mapBinaryInplace(self, function(a,b) if b >= other then return 1 else return 0 end end)
  end
  return result
end

function Array.lt(self,other)
  local result = Array.create(self.shape, Array.int8)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b < c then return 1 else return 0 end end)
  else
    result:mapBinaryInplace(self, function(a,b) if b < other then return 1 else return 0 end end)
  end
  return result
end

function Array.le(self,other)
  local result = Array.create(self.shape, Array.int8)
  if isnarray(other) then
    -- asume Array table
    result:mapTenaryInplace(self, other, function(a,b,c) if b <= c then return 1 else return 0 end end)
  else
    result:mapBinaryInplace(self, function(a,b) if b <= other then return 1 else return 0 end end)
  end
  return result
end


Array.__add = Array.add
Array.__sub = Array.sub
Array.__mul = Array.mul
Array.__div = Array.div




function Array.all(self)
  local all_one = true
  self:mapInplace(function(a) if a ~= 1 then all_one = false end return a end)
  return all_one
end

function Array.any(self)
  local any_one = false
  self:mapInplace(function(a) if a == 1 then any_one = true end return a end)
  return all_one
end

function Array.lookup(self,lut)
-- lookup values in table based on array element values
--
-- required
--  lut : the lookup table to be used
  local result = Array.create(self.shape, lut.dtype)
  local temp_lut = lut
  result:mapBinaryInplace( self, function(a,b) return temp_lut.data[b] end)
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


function Array.nonzero(self)
-- get coord table of nonzero elements

   -- reset shared upvalues
  _nonzero_count = 0
  _nonzero_ndim = #self.shape

  -- determine number of nonzero elements
  self:mapInplace(_nonzero_count_nz)

  -- allocate arrays for dimension indices
  _nonzero_result = {}
  for i=1,_nonzero_ndim,1 do
    _nonzero_result[i] = Array.create({_nonzero_count},Array.int32)
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

return Array            
