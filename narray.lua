--  ljarray.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD
--
--
--
-- Observed LUAJIT strangeness:
--
--   calling a function defined as Array:function(a,b,c) 
--   is *MUCH* slower then calling the same cunfction
--   defined as Array.function(self, ab, c) ?
--
--
local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers") 

local Array = {}
Array.__index = Array

Array.int8 = ffi.typeof("char[?]");
Array.int32 = ffi.typeof("int[?]");
Array.int64 = ffi.typeof("long[?]");
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
 }


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
    -- these methods are SLOOOW!
    self.get = self.getN
    self.getPos = self.getPosN
    self.set = Array.set1
    self.setPos = Array.setPosN
  end
end

function Array.fromData(ptr, dtype, shape, strides, source)
  local array = {}
  setmetatable(array,Array)
  array.data = ptr
  array.dtype = dtype
  array.strides = strides
  array.shape = shape
  if source == nil then
    array.source = array    
  else
    array.source = source
  end
  -- calculate size (number of elements)
  array.size = helpers.reduce(operator.mul, shape, 1)
  array:fixMethodsDim()
  return array
end

function Array.create(shape, dtype)
   -- calculate strides.
   -- LUAJIT:for some reason using a lua table seems to be faster 
   -- then using a native array  , probably because
   -- native arrays alsays on heap ?
   local strides = {} --ffi.new(Array.int32,#shape+1)
   strides[#shape] = 1
   for i = #shape-1,1,-1 do
     strides[i] = shape[i+1] * strides[i+1]
   end
   
   -- allocate data, do not initialize !
   -- the {0} is a trick to prevent zero
   -- filling. 
   -- BEWARE: array is uninitialized 
   local size = helpers.reduce(operator.mul, shape, 1)
   local data = dtype(size, {0})

   return Array.fromData(data,dtype,shape,strides)
end

function Array.view(self,start, stop)
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
  local data = self.data + self.strides[dimension]*(start)
  local shape = {}
  local strides = {}
  if stop == nil then
    for i=1,dimension,1 do
      array.strides[i] = self.strides[i]
      array.shape[i] = self.shape[i]
    end
    for i=dimension+1,#self.shape,1 do
      array.strides[i-1] = self.strides[i]
      array.shape[i-1] = self.shape[i]
    end
  else
    shape = copy(self.shape)
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

local getMapInplace = function()
  return function(self,f, call_with_position)
    local temp, offset, i
    local pos = helpers.binmap(operator.sub, self.shape, self.shape)
    local ndim = self.ndim
    local d = 1
    local offseta = 0

    while pos[1] < self.shape[1] do
      if d == ndim then
        -- iterate over array
        local stride = self.strides[d]
        local stop = (self.shape[d]-1 ) *stride
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
    end
  end
end

Array.mapInplace = getMapInplace()

--
--  Optimally, we would like to implement the binary map
--  function with the help of the unary map and the position
--  argument. Unfortunately luajit cannot optimize away all
--  of the additional overhead that the following 
--  implementatino incurs:
--
--           function Array.mapBinaryInplace(self,f,other, call_with_position)
--             local helpers.binmapper
--             local _f = f
--             local _other = other
--             if call_with_position ~= true then
--               helpers.binmapper = function(a,pos)
--                 return _f(a,_other:getPos(pos))
--               end
--             else
--               helpers.binmapper = function(a,pos)
--                 return _f(a,_other:getPos(pos),pos)
--               end
--             end
--             self:mapInplace(helpers.binmapper, true)
--           end

function Array.mapBinaryInplace(self,f,other, call_with_position)
  local temp_a, temp_b, offset_a, offset_b, i
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = self.ndim
  local d = 1
  local base_offset_a = 0
  local base_offset_b = 0
  local fct = other.get3
  local fct2 = other.get

  while pos[1] < self.shape[1] do
    --print(helpers.to_string(pos))
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
  end
end

function Array.mapTenaryInplace(self,f,other_b, other_c, call_with_position)
  local temp_a, temp_b, temp_c, offset_a, offset_b, offset_c, i
  local pos = helpers.binmap(operator.sub, self.shape, self.shape)
  local ndim = #self.shape
  local d = 1
  local base_offset_a = 0
  local base_offset_b = 0
  local base_offset_c = 0

  while pos[1] < self.shape[1] do
    --print(helpers.to_string(pos))
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
  local offset = helpers.reduce(operator.add, helpers.binmap(operator.mul, pos, self.strides), 0)
  self.data[offset] = val
end

function Array.setCoordinates(self,coord, data)
  local update_values
  if type(data) == "table" then
    assert(#data.shape == 1)
    update_values = function(a, coord_index)
      return data.data[coord_index*data.strides[1]]
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
  assert(#indices == self.ndim)
  local result = Array.create({indices[1].shape[1]}, self.dtype)
  local update_values = function(a, index)
    result.data[index] = a -- the new array has no strides
    return a
  end
  self:mapCoordinates(indices, update_values)
  return result
end

function Array.assign(self,data)
  if type(data) == "table" then
    -- asume Array table
    self:mapBinaryInplace( function(a,b) return b end )
  else
    self:mapInplace( function(x) return data end )
  end
end

function Array.add(self,other)
  if type(other) == "table" then
    -- asume Array table
    self:mapBinaryInplace(function(a,b) return a+b end, other)
  else
    self:mapInplace(function(a) return a + other end)
  end
end

function Array.sub(self,other)
  if type(other) == "table" then
    -- asume Array table
    self:mapBinaryInplace(function(a,b) return a-b end, other)
  else
    self:mapInplace(function(a) return a - other end)
  end
end

function Array.mul(self,other)
  if type(other) == "table" then
    -- asume Array table
    self:mapBinaryInplace(function(a,b) return a*b end, other)
  else
    self:mapInplace(function(a) return a * other end)
  end
end

function Array.div(self,other)
  if type(other) == "table" then
    -- asume Array table
    self:mapBinaryInplace(function(a,b) return a / b end, other)
  else
    self:mapInplace(function(a) return a / other end)
  end
end

function Array.eq(self,other)
  local result = Array.create(self.shape, Array.int8)
  if type(other) == "table" then
    -- asume Array table
    result:mapTenaryInplace(function(a,b,c) if b == c then return 1 else return 0 end end, self, other)
  else
    result:mapBinaryInplace(function(a,b) if b == other then return 1 else return 0 end end, self)
  end
  return result
end

function Array.neq(self,other)
  local result = Array.create(self.shape, Array.int8)
  if type(other) == "table" then
    -- asume Array table
    result:mapTenaryInplace(function(a,b,c) if b == c then return 0 else return 1 end end, self, other)
  else
    result:mapBinaryInplace(function(a,b) if b == other then return 0 else return 1 end end, self)
  end
  return result
end

function Array.gt(self,other)
  local result = Array.create(self.shape, Array.int8)
  if type(other) == "table" then
    -- asume Array table
    result:mapTenaryInplace(function(a,b,c) if b > c then return 1 else return 0 end end, self, other)
  else
    result:mapBinaryInplace(function(a,b) if b > other then return 1 else return 0 end end, self)
  end
  return result
end

function Array.ge(self,other)
  local result = Array.create(self.shape, Array.int8)
  if type(other) == "table" then
    -- asume Array table
    result:mapTenaryInplace(function(a,b,c) if b >= c then return 1 else return 0 end end, self, other)
  else
    result:mapBinaryInplace(function(a,b) if b >= other then return 1 else return 0 end end, self)
  end
  return result
end

function Array.lt(self,other)
  local result = Array.create(self.shape, Array.int8)
  if type(other) == "table" then
    -- asume Array table
    result:mapTenaryInplace(function(a,b,c) if b < c then return 1 else return 0 end end, self, other)
  else
    result:mapBinaryInplace(function(a,b) if b < other then return 1 else return 0 end end, self)
  end
  return result
end

function Array.le(self,other)
  local result = Array.create(self.shape, Array.int8)
  if type(other) == "table" then
    -- asume Array table
    result:mapTenaryInplace(function(a,b,c) if b <= c then return 1 else return 0 end end, self, other)
  else
    result:mapBinaryInplace(function(a,b) if b <= other then return 1 else return 0 end end, self)
  end
  return result
end

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
  local result = Array.create(self.shape, lut.dtype)
  local temp_lut = lut
  result:mapBinaryInplace( function(a,b) return temp_lut.data[b] end, self)
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

-- test: create a special mapper for nonzero so that luajit compiles a fresh trace for this function
local _nonzero_mapInplace = getMapInplace()

function Array.nonzero(self)
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


local _print_element = function(x)
  io.write(x, " ")
  return x
end

function Array.print(self)
  io.write("---------------\n")
  self:mapInplace( _print_element)
  io.write("\nArray", tostring(self), "(shape = ", helpers.to_string(self.shape))
  io.write(", stride = ", helpers.to_string(self.strides))
  io.write(", dtype = ", tostring(self.dtype), ")\n")
  io.write("---------------\n")
end


return Array
