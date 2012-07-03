--  narray_math.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isnarray = helpers.isnarray

local _add_constant_value
local _add_constant = function(x)
  return x + _add_constant_value
end

function Array.add(self,other)
  if isnarray(other) then
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
