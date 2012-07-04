--  narray_base.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isnarray = helpers.isnarray


function Array.coordinates(self)
-- array iterator that yields a coordinate which is a zero-based table
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 0

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
  d = ndim - 1
  pos[d] = -1
  local dim_count = self.shape[ndim-1]

  return function()
    -- print("pos: ", helpers.to_string(pos), d)
    if dim_count == 0 then
      dim_count = self.shape[ndim-1]
      pos[d] = -1
      d = d - 1
      -- hadle 1-dimensional case
      if d < 0 then
        return nil
      end
      pos[d] = pos[d] + 1
      while pos[d] >= self.shape[d] do
        if pos[0] == self.shape[0] then
          return nil
        end
        pos[d] = 0
        d = d - 1
        pos[d] = pos[d] + 1
      end
      d = ndim - 1
    end
    dim_count = dim_count - 1
    pos[d] = pos[d] + 1
    return pos
  end
end



function Array.values(self)
-- array iterator that yields the array value at each coordinate
--
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 0
  local offset = 0
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
  d = ndim - 1
  pos[d] = -1
  local stride = self.strides[d]
  local stop = (self.shape[d]-1 )*stride

  return function()
    -- print("pos: ", helpers.to_string(pos), d)
    if offset >= stop then
      offset = -stride
      pos[d] = -1
      d = d - 1
      pos[d] = pos[d] + 1
      offseta = offseta + self.strides[d]
      while pos[d] >= self.shape[d] do
        if pos[0] == self.shape[0] then
          return nil
        end
        pos[d] = 0
        offseta = offseta - (self.shape[d])*self.strides[d]
        d = d - 1
        -- hadle 1-dimensional case
        if d < 0 then
          return nil
        end
        pos[d] = pos[d] + 1
        offseta = offseta + self.strides[d]
      end
      d = ndim - 1
    end
    pos[d] = pos[d] + 1
    offset = offset + stride
    return self.data[offseta + offset]
  end
end

function Array.pairs(self)
-- array iterator that yields the coordinate as 
-- a zero based table and the array value at each coordinate
--
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 0
  local offset = 0
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
  d = ndim - 1
  local stride = self.strides[d]
  local stop = (self.shape[d]-1 )*stride

  return function()
    -- print("pos: ", helpers.to_string(pos), d)
    if offset >= stop then
      offset = -stride
      pos[d] = -1
      d = d - 1
      pos[d] = pos[d] + 1
      offseta = offseta + self.strides[d]
      while pos[d] >= self.shape[d] do
        if pos[0] == self.shape[0] then
          return nil, nil
        end
        pos[d] = 0
        offseta = offseta - (self.shape[d])*self.strides[d]
        d = d - 1
        -- hadle 1-dimensional case
        if d < 0 then
          return nil
        end
        pos[d] = pos[d] + 1
        offseta = offseta + self.strides[d]
      end
      d = ndim - 1
    end
    pos[d] = pos[d] + 1
    offset = offset + stride
    return pos, self.data[offseta + offset]
  end
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
      d = ndim - 1
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
      pos[d] = 0
      d = d - 1
      -- hadle 1-dimensional case
      if d < 0 then
        break
      end
      pos[d] = pos[d] + 1
      offseta = offseta + self.strides[d]
      while (pos[d] >= self.shape[d]) and (pos[0] ~= self.shape[0]) do
        pos[d] = 0
        offseta = offseta - (self.shape[d])*self.strides[d]
        d = d - 1
        pos[d] = pos[d] + 1
        offseta = offseta + self.strides[d]
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
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 0
  local offset_a = 0
  local offset_b = 0
  assert(self.ndim == other.ndim)
  assert(self.size == other.size)

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
    d = ndim - 1
    pos[d] = 0
    -- print("pos: ", helpers.to_string(pos), d)
    -- iterate over array
    local offset_b2 = 0
    local stride_a = self.strides[d]
    local stride_b = other.strides[d]
    local stop = self.shape[d]*stride_a - 1
    if call_with_position ~= true then
      for offset_a2=0,stop,stride_a do
        local val_a = self.data[offset_a + offset_a2]
        self.data[offset_a + offset_a2] = f(val_a, other.data[offset_b + offset_b2])
        offset_b2 = offset_b2 + stride_b
      end
    else
      for offset_a2=0,stop,stride_a do
        self.data[offset_a + offset_a2] = f(self.data[offset_a + offset_a2], other.data[offset_b + offset_b2], pos)
        offset_b2 = offset_b2 + stride_b
        pos[d] = pos[d] + 1
      end
    end
    pos[d] = 0
    d = d - 1
    -- hadle 1-dimensional case
    if d < 0 then
      break
    end
    pos[d] = pos[d] + 1
    offset_a = offset_a + self.strides[d]
    offset_b = offset_b + other.strides[d]
    while (pos[d] >= self.shape[d]) and (pos[0] ~= self.shape[0]) do
      pos[d] = 0
      offset_a = offset_a - (self.shape[d])*self.strides[d]
      offset_b = offset_b - (other.shape[d])*other.strides[d]
      d = d - 1
      pos[d] = pos[d] + 1
      offset_a = offset_a + self.strides[d]
      offset_b = offset_b + other.strides[d]
    end
    -- print("blubb1")
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
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 0
  local offset_a = 0
  local offset_b = 0
  local offset_c = 0
  assert(self.ndim == other_b.ndim)
  assert(other_b.ndim == other_c.ndim)
  local sum_diff = helpers.reduce(operator.add, helpers.binmap(operator.sub, other_b.shape, other_c.shape), 0)
  assert( sum_diff == 0, sum_diff)

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
    d = ndim - 1
    pos[d] = 0
    --print("pos: ", helpers.to_string(pos), d)
    -- iterate over array
    local offset_b2 = 0
    local offset_c2 = 0
    local stride_a = self.strides[d]
    local stride_b = other_b.strides[d]
    local stride_c = other_c.strides[d]
    local stop = self.shape[d]*stride_a - 1
    if call_with_position ~= true then
      for offset_a2=0,stop,stride_a do
        local val_a = self.data[offset_a + offset_a2]
        self.data[offset_a + offset_a2] = f(val_a, other_b.data[offset_b + offset_b2],other_c.data[offset_c + offset_c2])
        offset_b2 = offset_b2 + stride_b
        offset_c2 = offset_c2 + stride_c
      end
    else
      for offset_a2=0,stop,stride_a do
        self.data[offset_a + offset_a2] = f(self.data[offset_a + offset_a2], other_b.data[offset_b + offset_b2],other_c.data[offset_c + offset_c2], pos)
        offset_b2 = offset_b2 + stride_b
        offset_c2 = offset_c2 + stride_c
        pos[d] = pos[d] + 1
      end
    end
    pos[d] = 0
    d = d - 1
    -- hadle 1-dimensional case
    if d < 0 then
      break
    end
    pos[d] = pos[d] + 1
    offset_a = offset_a + self.strides[d]
    offset_b = offset_b + other_b.strides[d]
    offset_c = offset_c + other_c.strides[d]
    while (pos[d] >= self.shape[d]) and (pos[0] ~= self.shape[0]) do
      pos[d] = 0
      offset_a = offset_a - (self.shape[d])*self.strides[d]
      offset_b = offset_b - (other_b.shape[d])*other_b.strides[d]
      offset_c = offset_c - (other_c.shape[d])*other_c.strides[d]
      d = d - 1
      pos[d] = pos[d] + 1
      offset_a = offset_a + self.strides[d]
      offset_b = offset_b + other_b.strides[d]
      offset_c = offset_c + other_c.strides[d]
    end
    -- print("blubb1")
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


local _nonzero_count = 0
local _nonzero_ndim = 0
local _nonzero_result
local _nonzero_update_indices = function(a,pos)
  if a ~= 0 then
    for i=0,_nonzero_ndim-1,1 do
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
  _nonzero_ndim = self.ndim

  -- determine number of nonzero elements
  self:mapInplace(_nonzero_count_nz)

  -- allocate arrays for dimension indices
  _nonzero_result = {}
  for i=0,_nonzero_ndim-1,1 do
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
  return self.data[i*self.strides[0]] 
end

function Array.get2(self,i,j)
  return self.data[i*self.strides[0] + j*self.strides[1]] 
end

function Array.get3(self, i,j,k)
  return self.data[i*self.strides[0] + j*self.strides[1] + k*self.strides[2]] 
end

function Array.get4(self,i,j,k,l)
  return self.data[i*self.strides[0] + j*self.strides[1] + k*self.strides[2] + l*self.strides[3]] 
end

function Array.getPos1(self, pos)
  return self:get1(pos[0])
end

function Array.getPos2(self, pos)
  return self:get2(pos[0],pos[1])
end

function Array.getPos3(self, pos)
  return self:get3(pos[0],pos[1],pos[2])
end

function Array.getPos4(self, pos)
  return self:get4(pos[0],pos[1],pos[2], pos[3])
end

function Array.getPosN(self,pos)
  -- TODO:implement
  error("")
end

function Array.set1(self, i, val)
  self.data[i*self.strides[0]] = val
end

function Array.set2(self, i,j, val)
  self.data[i*self.strides[0] + j*self.strides[1]] = val
end

function Array.set3(self, i,j,k, val)
  self.data[i*self.strides[0] + j*self.strides[1] + k*self.strides[2]] = val
end

function Array.set4(self, i,j,k,l, val)
  self.data[i*self.strides[0] + j*self.strides[1] + k*self.strides[2] + l*self.strides[3]] = val
end

function Array.setN(self,val, ...)
  self:setPosN(...,val)
end

function Array.setPos1(self, pos, val)
  self:set1(pos[0],val)
end

function Array.setPos2(self, pos, val)
  self:set2(pos[0],pos[1],val)
end

function Array.setPos3(self, pos, val)
  self:set3(pos[0],pos[1],pos[2],val)
end

function Array.setPos4(self, pos, val)
  self:set4(pos[0],pos[1],pos[2],pos[3],val)
end

function Array.setPosN(self, pos, val)
  -- TODO: slooow
  local offset = helpers.reduce(operator.add, helpers.binmap(operator.mul, pos, self.strides), 0)
  self.data[offset] = val
end

function Array.fixMethodsDim(self)
-- helper method that specializes some critical functions depending
-- on the number of dimensions of the array
  self.ndim = self.ndim
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
