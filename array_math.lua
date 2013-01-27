--  narray_math.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isarray = helpers.isarray

local _add_constant_value
local _add_constant = function(x)
  return x + _add_constant_value
end

function Array.add(self,other)
  if isarray(other) then
    self:mapBinaryInplace(other, operator.add)
  else
    _add_constant_value = other
    self:mapInplace(_add_constant)
  end
  return self
end


local _sub_constant_value
local _sub_constant = function(x)
  return x - _sub_constant_value
end

function Array.sub(self,other)
  if isarray(other) then
    self:mapBinaryInplace(other, operator.sub)
  else
    _sub_constant_value = other
    self:mapInplace(_sub_constant)
  end
  return self
end

local _mul_constant_value
local _mul_constant = function(x)
  return x * _mul_constant_value
end

function Array.mul(self,other)
  if isarray(other) then
    self:mapBinaryInplace(other, operator.mul)
  else
    _mul_constant_value = other
    self:mapInplace(_mul_constant)
  end
  return self
end


local _div_constant_value
local _div_constant = function(x)
  return x / _div_constant_value
end

function Array.div(self,other)
  if isarray(other) then
    self:mapBinaryInplace(other, operator.div)
  else
    _div_constant_value = other
    self:mapInplace(_div_constant)
  end
  return self
end


local _eq_constant_value
local _eq_constant = function(a,b)
  if b == _eq_constant_value then
    return 1
  else 
    return 0
  end
end

local _eq = function(a,b,c) if b == c then return 1 else return 0 end end

function Array.eq(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isarray(other) then
    result:mapTenaryInplace(self, other, _eq)
  else
    _eq_constant_value = ffi.cast(self.dtype, other)
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

local _neq = function(a,b,c) if b == c then return 0 else return 1 end end

function Array.neq(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isarray(other) then
    result:mapTenaryInplace(self, other, _neq)
  else
    _neq_constant_value = ffi.cast(self.dtype, other)
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

local _gt = function(a,b,c) if b > c then return 1 else return 0 end end

function Array.gt(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isarray(other) then
    result:mapTenaryInplace(self, other, _gt)
  else
    _gt_constant_value = ffi.cast(self.dtype, other)
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

local _ge = function(a,b,c) if b >= c then return 1 else return 0 end end

function Array.ge(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isarray(other) then
    result:mapTenaryInplace(self, other, _ge)
  else
    _ge_constant_value = ffi.cast(self.dtype, other)
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

local _lt = function(a,b,c) if b < c then return 1 else return 0 end end

function Array.lt(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isarray(other) then
    result:mapTenaryInplace(self, other, _lt)
  else
    _lt_constant_value = ffi.cast(self.dtype, other)
    result:mapBinaryInplace(self, _lt_constant)
  end
  return result
end


local _le_constant_value
local _le_constant = function(a,b)
  if b <= _le_constant_value then
    return 1
  else
    return 0
  end
end

local _le = function(a,b,c) if b <= c then return 1 else return 0 end end

function Array.le(self,other, order)
  local result = Array.create(self.shape, Array.int8, order)
  if isarray(other) then
    result:mapTenaryInplace(self, other, _le)
  else
    _le_constant_value = ffi.cast(self.dtype, other)
    result:mapBinaryInplace(self, _le_constant)
  end
  return result
end


local _all_result
local _all = function(a, pos)
  if a == 0 then
    _all_result = false
  end
  return a
end

function Array.all(self)
  _all_result = true
  self:mapInplace(_all, true)
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


local _max_result
local _find_max = function(a)
  if a > _max_result then
      _max_result = a
  end
  return a
end

--- get element of maximum value
function Array.max(self)
  _max_result = self.data[0]
  self:mapInplace(_find_max)
  return _max_result
end



local _min_result
local _find_min = function(a)
  if a < _min_result then
      _min_result = a
  end
  return a
end

--- get element of minimum value
function Array.min(self)
  _min_result = self.data[0]
  self:mapInplace(_find_min)
  return _min_result
end


local _sum_result
local _find_sum = function(a)
  _sum_result = _sum_result + a
  return a
end

--- get sum of elements
function Array.sum(self)
  _sum_result = 0
  self:mapInplace(_find_sum)
  return _sum_result
end

--- get average of elements
function Array.avg(self)
  return self:sum() / self.size
end


--- shift array by n elements
function Array.shift(self, n)
    assert(self.ndim == 1)
    local copy = self:copy()

    local target = n
    if target < 0 then
        target = self.shape[0] + target
    end
    for i = 0, self.shape[0]-1, 1 do
        self:set(target, copy:get(i))
        target = target + 1
        if target == self.shape[0] then
            target = 0
        end
    end
end

--- count how often each value occurs in the data
function Array.histogram(self)
    local max = math.ceil(self:max())
    local result = Array.zeros({max+1}, Array.int32)
    for v in self:values() do
        v = math.ceil(v)
        result.data[v] = result.data[v] + 1
    end
    return result
end


local _clip_low
local _clip_high
local _clip = function(a)
  a = math.min(a, _clip_high)
  a = math.max(a, _clip_low)
  return a
end

--- clip values to range
function Array.clip(self, low, high)
    _clip_low = low
    _clip_high = high
    self:mapInplace(_clip)
    return self
end

local _abs = function(a)
    return math.abs(a)
end

--- absolute values
function Array.abs(self)
    self:mapInplace(_abs)
    return self
end
