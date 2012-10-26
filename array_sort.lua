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

-- local function inssort(v, low, high, comp, swap, swaparg)
--   for i = low, high do
--     local idx = i
--     for j = i+1, high do
--       if comp(v.data[j], v.data[idx]) then
--         idx = j
--       end
--     end
--     if idx ~= i then
--       local temp = v.data[idx]
--       v.data[idx] = v.data[i]
--       v.data[i] = temp
--       swap(swaparg, idx, i)
--     end
--   end
--   return nil, high, low
-- end



-- default comparison function
local _default_comp = function(a,b)
  return a < b
end

-- default empty swap function
local _default_swap = function(i1,i2)
end

local med3 = function(t, a,b,c, comp)
  if comp(t.data[a], t.data[b]) then
    if comp(t.data[b], t.data[c]) then
      return b
    else
      if comp(t.data[a], t.data[c]) then
        return c
      else
        return a
      end
    end
  else
    if comp(t.data[a], t.data[c]) then
      return a 
    else
      if comp(t.data[b], t.data[c]) then
        return c
      else
        return b
      end
    end
  end
end

local med9 = function(t, start, stop, comp)
  local n = stop - start
  local mid = start + bitop.rshift(n,1)
  local step = bitop.rshift(n, 3)
  local step2 = bitop.lshift(step,1)

  local p1 = med3(t, start, start + step, start + step2, comp)
  local p2 = med3(t, mid - step, mid, mid +step, comp)
  local p3 = med3(t, stop - step2, stop - step, stop, comp)

  return med3(t, p1, p2, p3, comp)
end

 --in-place quicksort
 local quicksort_impl
 quicksort_impl = function(t, comp,swap,start, endi, swaparg)
   local n = endi - start
   if n < 40 then
     inssort(t,start,endi, comp, swap, swaparg)
     return t
   end

  -- random pivot choice
  -- local pivot = math.random(start,endi)
  local mid = start + bitop.rshift(endi-start,1)
  local pivot = med3(t, start, mid, endi, comp)
  -- local pivot = med9(t, start, endi, comp)

  swap(swaparg, start, pivot)
  local temp = t.data[start]
  t.data[start] = t.data[pivot]
  t.data[pivot] = temp

  local  i = start
  local  j = endi+1

  while true do
    repeat
      i = i + 1
    until not (comp(t.data[i],t.data[start]) and i <= endi)
    repeat
      j = j - 1
    until not comp(t.data[start], t.data[j])
    if j < i then    
      break
    end
    swap(swaparg, i, j)
    temp = t.data[i]
    t.data[i] = t.data[j]
    t.data[j] = temp
  end
  pivot = j
  swap(swaparg,start, pivot)
  temp = t.data[start]
  t.data[start] = t.data[pivot]
  t.data[pivot] = temp

  -- recurse using tail call optimization
  if pivot - start < endi - i then
    quicksort_impl(t,comp,swap,start, pivot -1, swaparg)
    return quicksort_impl(t,comp,swap,i , endi, swaparg)
  else
    quicksort_impl(t,comp,swap,i, endi, swaparg)
    return quicksort_impl(t,comp,swap,start, pivot-1 , swaparg)
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
-- sort the array inplace
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
  return self
end

local _swapper = function(indices, a,b)
  local temp = indices.data[a]
  indices.data[a] = indices.data[b]
  indices.data[b] = temp
end

Array.argsort = function(self, axis, comp, start, stop, out, inplace)
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
  elseif inplace == true then
    copy = self
    indices = Array.arange(0,self.shape[0])
  else
    copy = self:copy()
    indices = Array.arange(0,self.shape[0])
  end


  quicksort(copy,comp,_swapper, indices, start, stop)

  local result  = {}
  result[1] = indices
  return result
end

