--  narray_sort.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isnarray = helpers.isnarray


-- insertion sort helper - used by quicksort for small ranges
local function inssort(v, low, high, comp, swap)
  for i = low+1, high do
    local elt = v.data[i]
    if comp(elt,v.data[low]) then
      for j = i-1, low, -1 do v.data[j+1] = v.data[j]; swap(j,j+1); end
      v.data[low] = elt
    else
      local j = i-1
      while comp(elt,v.data[j]) do v.data[j+1] = v.data[j]; swap(j,j+1); j = j - 1 end
      v.data[j+1] = elt
    end
  end
  return nil, high, low
end

local _default_comp = function(a,b)
  return a <= b
end

local _default_swap = function(i1,i2)
end

--in-place quicksort
local quicksort_impl
quicksort_impl = function(t, comp,swap,start, endi)
  if endi-start < 20 then
    inssort(t,start,endi, comp, swap)
    return t
  end
  --partition w.r.t. first element
  if not comp(t.data[start],t.data[start+1]) then
    local temp = t.data[start+1]
    t.data[start+1] = t.data[start]
    t.data[start] = temp
    swap(start,start+1)
  end
  local pivot = start
  for i = start + 2, endi do
    if comp(t.data[i],t.data[pivot]) then
      local temp = t.data[pivot + 1]
      t.data[pivot + 1] = t.data[pivot]
      t.data[pivot] = t.data[i]
      t.data[i] = temp
      swap(pivot,pivot+1)
      swap(pivot,i)
      pivot = pivot + 1
    end
  end
  -- recurse using tail call optimization
  if pivot - start < endi - pivot then
    quicksort_impl(t,comp,swap,start, pivot - 1)
    return quicksort_impl(t,comp,swap,pivot + 1, endi)
  else
    quicksort_impl(t,comp,swap,pivot + 1, endi)
    return quicksort_impl(t,comp,swap,start, pivot - 1)
  end
end

local quicksort = function(t,comp,swap)
  assert(t.ndim == 1, "quicksort only works for dense 1-d arrays - ndim: " .. t.ndim)
  assert(t.strides[0] == 1, "quicksort only works for dense 1-d arrays - strides[0]: " .. t.strides[0])

  swap = swap or _default_swap
  comp = comp or _default_comp
  local start, endi = 0, t.shape[0]-1
  quicksort_impl(t,comp, swap, start,endi)
end

Array.sort = function(self, axis, comp, swap)
-- Return a sorted copy of an array.
-- 
-- Parameters :	
-- axis : int or nil, optional
--        Axis along which to sort. If None, the array is flattened before sorting. 
--        the default is nil which sorts along the last axis
--
  if axis == nil then
    axis = self.ndim -1 -- last axis default
  end
  assert(axis < self.ndim, "narray.sort: sort axis larger then number of dimensions")
  
  -- construct helper view with singleton dimension in axis
  local start = helpers.zeros(self.ndim)
  local stop = helpers.zeros(self.ndim)
  for i = 0, self.ndim - 1 do
    if i ~= axis then
      stop[i] = self.shape[i]
    else
      stop[i] = 1
    end
  end
  local view = self:view(start,stop)

  -- iterate over coordinates and sort along axis
  for pos in view:coordinates() do
    -- bind line
    local line = self
    for i = 0, axis-1 do
      line = line:bind(0,pos[i])
    end
    for i = axis+1, self.ndim-1 do
      line = line:bind(1,pos[i])
    end
    
    -- copy line to dense array
    local line2
    if line.strides[0] == 1 then
      line2 = line
    else
      line2 = Array.create({self.shape[axis]},self.dtype)
      line2:assign(line)
    end
    
    -- finally, sort!
    quicksort(line2,comp,swap)
    
    -- copy back
    if line2 ~= line then
      line:assign(line2)
    end
  end
end

Array.argsort = function(self, axis, comp)
-- Return the coordinates array if it were sorted.
-- i.e. array:getCoordinates(array:argsort()) equals array:sort()
-- 
-- Parameters :	
-- axis : int or nil, optional
--        Axis along which to sort. If None, the array is flattened before sorting. 
--        the default is nil which sorts along the last axis
--
  if axis == nil then
    axis = self.ndim -1 -- last axis default
  end
  --TODO: support multidimensional arrays
  assert(axis < self.ndim, "narray.argsort: sort axis larger then number of dimensions")
  assert(self.ndim == 1, "narray.argsort for now only supports 1-d arrays")

  local copy = self:copy()
  local indices = Array.arange(0,self.shape[0])

  local swapper = function(a,b)
    local temp = indices.data[a]
    indices.data[a] = indices.data[b]
    indices.data[b] = temp
  end

  copy:sort(axis,comp,swapper)
  local coordinates = {}
  coordinates[0] = indices
  return coordinates
end

