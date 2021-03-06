--  narray_base.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isarray = helpers.isarray

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
  if isarray(data) then
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
  if self.ndim == 1 then
    indices = indices[0]
    for i = 0, indices.shape[0]-1 do
      _get_coord_result.data[i] = self:get(indices:get(i))
    end
  else
    self:mapCoordinates(indices, _get_coord_update_values)
  end
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

  if b == nil or type(b) == "string" then -- assume static call
    local order = b
    b = a
    a = boolarray
    assert(self.shape ~= nil)
    boolarray = self
    local dtype = Array.float32
    local shape = nil
    if isarray(a) then
      dtype = a.dtype
      shape = a.shape
    elseif isarray(b) then
      dtype = b.dtype
      shape = b.shape
    else
      shape = boolarray.shape
    end
    self = Array.create(shape, dtype, order)
  end

  local nz = boolarray:nonzero()
  self:assign(b)
  if isarray(a) then 
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
  if isarray(data) then
    self:mapBinaryInplace(data, operator.assign)
  else
    _assign_constant_value = data
    self:mapInplace( _assign_constant )
  end
  return self
end


local _lookup_lut
local _lookup = function(a,b)
  return _lookup_lut:get(b)
end

---- lookup values/subarrays in array lut based on array element values
--
-- @param lut the lookup table to be used
--        if the lut is not a vector but a more-dimensional array
-- @param axis optional, if lut is multi-dimensional determines
--        along which axis the the lut is sliced into the result
-- @returns array
--        the result array will have self.ndim+lut.ndim-1 dimensions
--        for each value and coordinate in self, the result will hold
--        the lut:bind(axis,value) subarray.
--
function Array.lookup(self,lut, axis)
  local shape = helpers.copy(self.shape)
  local small_shape = {}
  local small_shape_offset = 0
  axis = axis or 0
  for d = 0, lut.ndim-1,1 do
    if d ~= axis then
        table.insert(shape, lut.shape[d])
        small_shape[d - small_shape_offset] = lut.shape[d]
    else
        small_shape_offset = 1
    end
  end

  local result = Array.create(shape, lut.dtype)
  
  if lut.ndim == 1 then
    _lookup_lut = lut
    result:mapBinaryInplace(self, _lookup)
  else
      local result_dim_offset = self.ndim
      local lut_other = lut:bind(axis, 0)

      for pos, val in lut_other:pairs() do
          local t_result = result
          local t_lut = lut
          for d = 0, lut_other.ndim-1,1 do
              t_result = t_result:bind(result_dim_offset, pos[d])
              if d >= axis then
                t_lut = t_lut:bind(1,pos[d])
              else
                t_lut = t_lut:bind(0,pos[d])
              end
          end
          assert(t_result.ndim == result_dim_offset)
          assert(t_lut.ndim == 1)
          local temp = self:lookup(t_lut)
          assert(temp.ndim == t_result.ndim)
          t_result:assign(temp)
      end
  end

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
  assert(self.ndim > 0)
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


function Array.extract(self, condition)
-- Return the elements of an array that satisfy some condition.
--
  assert(helpers.isarray(condition), "narray.extract: condition must be of type narray")
  assert(helpers.equal(self.shape, condition.shape), "narray.extract: condition and the array must be of equal shape")
  local coords = condition:nonzero() 
  return self:getCoordinates(coords)
end

function Array.take_slices(self, indices, axis)
-- take slices of array along axis for given indices
--
  assert(helpers.isarray(self), "narray.take_slices: first argument is not a narray")
  assert(indices.ndim == 1, "narray.take_slices: indices is not a one-dimensional narray")

  local shape = helpers.copy(self.shape)
  shape[axis] = indices.shape[0]
  local result = Array.create(shape, self.dtype, self.order)

  if self.ndim == 1 then  -- specialize for one dim for speed 
    for i = 0, indices.shape[0]-1 do
      result:set(i,self:get(indices:get(i)))
    end
  elseif self.ndim == 2 then -- specialize for two dims for speed
    if axis == 0 then
      for j = 0, self.shape[1]-1 do
        for i = 0, indices.shape[0]-1 do
          result:set(i,j,self:get(indices:get(i),j))
        end
      end
    else
      for j = 0, self.shape[0]-1 do
        for i = 0, indices.shape[0]-1 do
          result:set(j,i,self:get(j,indices:get(i)))
        end
      end
    end
  else
    local start = helpers.zeros(self.ndim)
    local stop = helpers.copy(self.shape)
    -- loop over indices and copy slice to result array
    for i = 0, indices.shape[0]-1 do

      start[axis] = i
      stop[axis] = i+1
      local dest = result:view(start,stop)
      
      start[axis] = indices:get(i)
      stop[axis] = indices:get(i) + 1
      local source = self:view(start,stop)

      dest:assign(source)
    end
  end

  return result
end

function Array.permute(self)
-- permute the array elements
--  
  local dest = {}

  for pos in self:coordinates() do
    for i = 0, self.ndim -1 do
      dest[i] = math.random(0,self.shape[i]-1)
    end
    local temp = self:getPos(pos)
    self:setPos(pos,self:getPos(dest))
    self:setPos(dest, temp)
  end
  return self
end

function Array.resize(self,shape, init)
-- resizes an array to a new shape.
--
-- number of dimensions must be the same.
-- intersecting shape contents are copied
--
  shape = helpers.zerobased(shape)
  local ndim = #shape+1
  assert(ndim == self.ndim, "narray.resize only supports resizing to same number of dimensions for now") -- .. self.ndim .. " vs " .. ndim)

  -- create new array with correct shape
  local new = Array.create(shape,self.dtype)
  
  if init ~= nil then
    new:assign(init)
  end

  -- determine intersection
  local intersection = {}
  for i = 0,ndim-1 do
    intersection[i] = math.min(self.shape[i],shape[i])
  end
  
  -- copy intersecting contents to new array
  local start = helpers.zeros(ndim)
  
  local view_source = self:view(start,intersection)
  local view_dest = new:view(start, intersection)

  view_dest:assign(view_source)

  self.shape = new.shape
  self.strides = new.strides
  self.data = new.data
  self.carray = new.carray
  self.size = new.size
  
  return self
end

--- concatenates a table of arrays along a given axis
-- 
-- @param arrays a table of arrays
-- @param axis optional, default = 0, the axis along which to stack
-- @returns array the stacked array
Array.concatenate = function(arrays, axis)
    axis = axis or 0
    local shape = helpers.copy(arrays[1].shape)
    local ndim = arrays[1].ndim
    local dtype = arrays[1].dtype
    local length = 0
    for i,a in ipairs(arrays) do
        for d = 0, ndim-1 do
            if d ~= axis then
                assert(a.ndim == ndim, "Array.concatenate: all arrays must be of same dimension!")
                assert(a.shape[d] == shape[d], "Array.concatenate: all arrays must be of same shape")
            end
        end
        length = length + a.shape[axis]
    end

    shape[axis] = length

    local result = Array.create(shape, dtype)
    local start = 0
    for i,a in ipairs(arrays) do
        local stop = start + a.shape[axis]
        local result_view = result:bind(axis, start, stop)
        result_view:assign(a)
        start = start + a.shape[axis]
    end
    
    return result
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

function Array.setN(self, ...)
  local offset = 0
  local pos = {...}
  for d = 0, self.ndim - 1 do
      offset = offset + self.strides[d]*pos[d+1]
  end
  self.data[offset] = pos[#pos]
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
  local offset = 0
  for d = 0, self.ndim-1 do
      offset = offset + self.strides[d]*pos[d]
  end
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
    self.set = Array.set4
    self.setPos = Array.setPos4
  else
    -- TODO: these methods are SLOOOW!
    self.get = self.getN
    self.getPos = self.getPosN
    self.set = Array.set1
    self.setPos = Array.setPosN
  end
end
