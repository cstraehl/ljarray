--  narray_sort.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isarray = helpers.isarray


-- insertion sort helper - used by quicksort_impl for small ranges
local function inssort(v, low, high, comp, swap, swaparg)
  for i = low+1, high do
    local elt = v.data[i]
    if comp(elt,v.data[low]) then
      for j = i-1, low, -1 do v.data[j+1] = v.data[j]; swap(swaparg,j,j+1); end
      v.data[low] = elt
    else
      local j = i-1
      while comp(elt,v.data[j]) do v.data[j+1] = v.data[j]; swap(swaparg,j,j+1); j = j - 1 end
      v.data[j+1] = elt
    end
  end
  return nil, high, low
end

-- default comparison function
local _default_comp = function(a,b)
  return a < b
end

-- default empty swap function
local _default_swap = function(i1,i2)
end


 --in-place quicksort
 local quicksort_impl
 quicksort_impl = function(t, comp,swap,start, endi, swaparg)
   if endi-start < 50 then
     inssort(t,start,endi, comp, swap, swaparg)
     return t
   end

  -- -- move median of first, middle and last element to front
  -- local mid = math.floor((start + endi) / 2)
  -- local mid_i = swap3(t, start, mid, endi-1, comp)
  -- swap(swaparg, start, mid_i)
  -- t.data[start], t.data[mid_i]= t.data[mid_i], t.data[start]

  -- random pivot choice
  local pivot = math.floor(math.random()*(endi-start)+start)
  swap(swaparg, start, pivot)
  local temp = t.data[start]
  t.data[start] = t.data[pivot]
  t.data[pivot] = temp

  --partition w.r.t. first element
  if not comp(t.data[start],t.data[start+1]) then
    local temp = t.data[start+1]
    t.data[start+1] = t.data[start]
    t.data[start] = temp
    swap(swaparg,start,start+1)
  end
  local pivot = start
  for i = start + 2, endi do
    if comp(t.data[i],t.data[pivot]) then
      local temp = t.data[pivot + 1]
      t.data[pivot + 1] = t.data[pivot]
      t.data[pivot] = t.data[i]
      t.data[i] = temp
      swap(swaparg,pivot,pivot+1)
      swap(swaparg,pivot,i)
      pivot = pivot + 1
    end
  end

  -- recurse using tail call optimization
  if pivot - start < endi - pivot then
    quicksort_impl(t,comp,swap,start, pivot - 1, swaparg)
    return quicksort_impl(t,comp,swap,pivot + 1, endi, swaparg)
  else
    quicksort_impl(t,comp,swap,pivot + 1, endi, swaparg)
    return quicksort_impl(t,comp,swap,start, pivot - 1, swaparg)
  end
end

-- quicksort helper
local quicksort = function(t,comp,swap,swaparg, start, stop)
  assert(t.ndim == 1) --, "quicksort only works for dense 1-d arrays - ndim: " .. t.ndim)
  assert(t.strides[0] == 1) --, "quicksort only works for dense 1-d arrays - strides[0]: " .. t.strides[0])

  swap = swap or _default_swap
  comp = comp or _default_comp
  start = start or 0
  stop = stop or t.shape[0]-1
  quicksort_impl(t,comp, swap, start,stop, swaparg)
end


Array.sort = function(self, axis, comp, starti, stopi)
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

  starti = starti or 0
  stopi = stopi or self.shape[axis]
  stopi = stopi - 1 -- quicksort takes inclusive ranges, we take exclusive stop
  
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
    quicksort(line2,comp,nil, nil, starti, stopi)
    
    -- copy back
    if line2 ~= line then
      line:assign(line2)
    end
  end
end

local _swapper = function(indices, a,b)
  local temp = indices.data[a]
  indices.data[a] = indices.data[b]
  indices.data[b] = temp
end

Array.argsort = function(self, axis, comp, start, stop, out)
-- Return the coordinates of array if it were sorted.
-- i.e. array:getCoordinates(array:argsort()) equals array:sort()
-- 
-- Parameters :	
-- axis : int or nil, optional
--        Axis along which to sort. 
--        the default is nil which sorts along the last axis
--
  if axis == nil then
    axis = self.ndim -1 -- last axis default
  end
  --TODO: support multidimensional arrays
  assert(axis < self.ndim, "narray.argsort: sort axis larger then number of dimensions")
  assert(self.ndim == 1, "narray.argsort for now only supports 1-d arrays")
  start = start or 0
  stop = stop or self.shape[0]
  stop = stop - 1 -- quicksort takes inclusive ranges, this functino takes exclusive stop range
  assert(stop > start)

  local copy
  local indices
  -- asume if out was given, we are allowed to sort inplace..
  -- otherwise make a copy
  if out ~= nil then
    assert(out.ndim == 1)
    assert(out.shape[0] >= stop)
    copy = self
    indices = out
  else
    copy = self:copy()
    indices = Array.arange(0,self.shape[0])
  end


  quicksort(copy,comp,_swapper, indices, start, stop-1)

  local result  = {}
  result[1] = indices
  return result
end

