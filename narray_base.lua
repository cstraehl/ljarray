--  narray_base.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isnarray = helpers.isnarray

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
    local d = 0
    local offseta = 0

    -- performance optimization for singleton dimensions
    local singletons = 0
    for i = ndim-1,0,-1 do
      if self.shape[i] == 1 then
        singletons = singletons + 1
      else
        break
      end
    end
    ndim = ndim - singletons


    while pos[0] < self.shape[0] do
      --print("pos: ", helpers.to_string(pos), d)
      if d == ndim-1 then
        -- iterate over array
        local stride = self.strides[d]
        local stop = (self.shape[d]-1 )*stride
        pos[d] = 0
        if call_with_position ~= true then
          for offset=0,stop,stride do
            self.data[offseta + offset] = f(self.data[offseta + offset])
          end
        else
          for offset=0,stop,stride do
            self.data[offseta + offset] = f(self.data[offseta + offset], pos)
            pos[d] = pos[d] + 1
          end
        end
        pos[d] = self.shape[d] - 1 
        offseta = offseta + (self.shape[d]-1)*self.strides[d]
      end
      if ((pos[d] == self.shape[d] - 1)and(d ~= 0)) then
        pos[d] = 0
        offseta = offseta - self.strides[d]*(self.shape[d]-1)

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
  assert(pos[0] ~= nil)
  local ndim = self.ndim
  assert(pos[ndim] == nil)
  local d = 0
  local base_offset_a = 0
  local base_offset_b = 0
    
  -- performance optimization for singleton dimensions
  local singletons = 0
  for i = ndim-1,0,-1 do
    if self.shape[i] == 1 then
      singletons = singletons + 1
    else
      break
    end
  end
  ndim = ndim - singletons


  while pos[0] < self.shape[0] do
    --print(helpers.to_string(pos), d)
    --print(base_offset_a, base_offset_b)

    if d == ndim - 1 then
      -- iterate over array
      local stride_a = self.strides[d]
      local stride_b = other.strides[d]
      offset_b = 0

      local stop = self.shape[d] *stride_a - 1
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

      pos[d] = self.shape[d]- 1
      base_offset_a = base_offset_a + (self.shape[d]-1)*self.strides[d]
      base_offset_b = base_offset_b + (other.shape[d]-1)*other.strides[d]
    end
    if ((pos[d] == self.shape[d] - 1)and(d ~= 0)) then
      pos[d] = 0
      base_offset_a = base_offset_a - self.strides[d]*(self.shape[d]-1)
      base_offset_b = base_offset_b - other.strides[d]*(other.shape[d]-1)

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
  assert(pos[0]~=nil)
  local ndim = self.ndim
  assert(pos[ndim] == nil)
  local d = 0
  local base_offset_a = 0
  local base_offset_b = 0
  local base_offset_c = 0
  
  -- performance optimization for singleton dimensions
  local singletons = 0
  for i = ndim-1,0,-1 do
    if self.shape[i] == 1 then
      singletons = singletons + 1
    else
      break
    end
  end
  ndim = ndim - singletons

  while pos[0] < self.shape[0] do
    --print(helpers.to_string(pos), d)
    if d == ndim-1 then
      -- iterate over array
      local stride_a = self.strides[d]
      local stride_b = other_b.strides[d]
      local stride_c = other_c.strides[d]

      offset_b = 0
      offset_c = 0

      local stop = self.shape[d] *stride_a -1
      pos[d] = 0

      for offset_a=0,stop,stride_a do
        temp_a = self.data[base_offset_a + offset_a]
        temp_b = other_b.data[base_offset_b + offset_b]
        temp_c = other_c.data[base_offset_c + offset_c]
        
        if call_with_position ~= true then
          self.data[base_offset_a + offset_a] = f(temp_a, temp_b, temp_c)
        else
          self.data[base_offset_a + offset_a] = f(temp_a, temp_b, temp_c, pos)
          pos[d] = pos[d] + 1
        end

        self.data[base_offset_a + offset_a] = f(temp_a, temp_b, temp_c)
        offset_b = offset_b + stride_b
        offset_c = offset_c + stride_c
      end

      pos[d] = self.shape[d] - 1
      base_offset_a = base_offset_a + (self.shape[d]-1)*self.strides[d]
      base_offset_b = base_offset_b + (other_b.shape[d]-1)*other_b.strides[d]
      base_offset_c = base_offset_c + (other_c.shape[d]-1)*other_c.strides[d]
    end
    if ((pos[d] == self.shape[d] - 1)and(d ~= 0)) then
      pos[d] = 0
      base_offset_a = base_offset_a - self.strides[d]*(self.shape[d]-1)
      base_offset_b = base_offset_b - other_b.strides[d]*(other_b.shape[d]-1)
      base_offset_c = base_offset_c - other_c.strides[d]*(other_c.shape[d]-1)

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
  assert(#coord == #self.shape, tostring(#coord ) .. " " .. tostring(#self.shape))

  local temp, offset, i
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 0
  
  -- precalculate offsets to prevent a small inner loop
  local offsets = Array.create(coord[0].shape, Array.int32)
  for i=0,coord[0].shape[0]-1,1 do
    offsets.data[i] = self.strides[0]*coord[0]:get1(i)
  end
  for j=1,ndim-1,1 do
    for i=0,coord[0].shape[0]-1,1 do
      offsets.data[i] = offsets.data[i] + self.strides[j]*coord[j]:get1(i)
    end
  end

  -- apply the function
  for i=0,coord[0].shape[0]-1,1 do
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
  local coord = helpers.zerobased(coord)
  assert(#coord  + 1 == self.ndim)
  _set_coord_data = data
  if isnarray(data) then
    assert(data.ndim == 1)
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
  local indices = helpers.zerobased(indices)
  assert(#indices  + 1 == self.ndim)
  _get_coord_result = Array.create({indices[0].shape[0]}, self.dtype)
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
    self:mapBinaryInplace(data, operator.assign)
  else
    _assign_constant_value = data
    self:mapInplace( _assign_constant )
  end
end
