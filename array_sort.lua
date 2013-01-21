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
local function inssort(v, low, high, swap, swaparg)
  for i = low+1, high,1 do
    local elt = v[i]
    if elt<v[low] then
      for j = i-1, low, -1 do
          v[j+1] = v[j]
          swap(swaparg,j,j+1)
      end
      v[low] = elt
    else
      local j = i-1
      while elt<v[j] do
          v[j+1] = v[j]
          swap(swaparg,j,j+1)
          j = j - 1
      end
      v[j+1] = elt
    end
  end
end


-- default empty swap function
local _default_swap = function(i1,i2)
end

local _swapper = function(data, a,b)
  local temp = data[a]
  data[a] = data[b]
  data[b] = temp
end


local med3 = function(t, a,b,c)
  if (t[a]< t[b]) then
    if (t[b]< t[c]) then
      return b
    else
      if (t[a]< t[c]) then
        return c
      else
        return a
      end
    end
  else
    if (t[a]< t[c]) then
      return a 
    else
      if (t[b]< t[c]) then
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
 quicksort_impl = function(data, swap,start, endi, swaparg)
   if endi - start < 32 then
     return
   end

  -- local mid = start + bitop.rshift(endi-start,1)
  -- local pivot = med3(t, start, mid, endi, comp)
  -- local pivot = med9(t, start, endi, comp)
  -- local pivot = start + bitop.rshift(endi-start,1)
  --pivot = med3(data, start, pivot, endi)
  local pivot = math.random(start,endi)
  local pv = data[pivot]

  swap(swaparg, endi, pivot)
  _swapper(data, endi, pivot)

  pivot = start
  for i = start, endi-1, 1 do
      if data[i] < pv then
          swap(swaparg, pivot, i)
          _swapper(data, pivot, i)
          pivot = pivot + 1
      end
  end
  swap(swaparg, endi, pivot)
  _swapper(data, endi, pivot)


  -- swap(swaparg, start, pivot)
  -- swap(data, start, pivot)

  -- local  i = start
  -- local  j = endi+1

  -- while true do
  --   repeat
  --     i = i + 1
  --   until not (data[i]<data[start] and i <= endi)
  --   repeat
  --     j = j - 1
  --   until not (data[start]< data[j])
  --   if j <= i then    
  --     break
  --   end
  --   swap(swaparg, i, j)
  --   swap(data, i, j)
  -- end
  -- pivot = j
  -- swap(swaparg,start, pivot)
  -- swap(data,start, pivot)

  quicksort_impl(data,swap,start, pivot-1, swaparg)
  quicksort_impl(data,swap,pivot+1 , endi, swaparg)
  
  -- -- recurse using tail call optimization
  -- if pivot - start < endi - pivot then
  --   quicksort_impl(data,swap,start, pivot -1, swaparg)
  --   quicksort_impl(data,swap,pivot+1 , endi, swaparg)
  -- else
  --   quicksort_impl(data,swap,pivot+1, endi, swaparg)
  --   quicksort_impl(data,swap,start, pivot-1 , swaparg)
  -- end
end

-- quicksort helper
local quicksort = function(t,swap,swaparg, start, stop)
  assert(t.ndim == 1) --, "quicksort only works for dense 1-d arrays - ndim: " .. t.ndim)
  assert(t.strides[0] == 1) --, "quicksort only works for dense 1-d arrays - strides[0]: " .. t.strides[0])

  start = start or 0
  stop = stop or t.shape[0]-1
  quicksort_impl(t.data, swap, start,stop, swaparg)
  inssort(t.data,start,stop, swap, swaparg)
end


local floatflip = function(f)
    local mask = bitop.bor(-bitop.rshift(f, 31),0x80000000)  
    return bitop.bxor(f, mask)
end

local ifloatflip = function(f)
    local mask = bitop.bor(bitop.rshift(f, 31) - 1,0x80000000)  
    return bitop.bxor(f, mask)
end

local _0 = function(x)
    return bitop.band(x, 0x7ff)
end

local _1 = function(x)
    return bitop.band(bitop.rshift(x,11), 0x7ff)
end

local _2 = function(x)
    return bitop.rshift(x,22)
end

local _radix_bins_t = ffi.typeof("int[6144]")

local radixsort = function(t, start, stop)
  assert(t.ndim == 1)
  assert(t.strides[0] == 1)
  start = start or 0
  stop = stop or t.shape[0]-1
    
  local temp1 = Array.create({t.shape[0]}, Array.int32)
  local temp2 = Array.create({t.shape[0]}, Array.int32)
  local data = ffi.cast("int32_t*", t.data)

  local b0 = _radix_bins_t()
  local b1 = b0 + 2048
  local b2 = b1 + 2048
  
  for i = 0, 3*2048-1, 1 do
      b0[i] = 0
  end
  
  -- count bins
  for i = start, stop, 1 do
    local fi = floatflip(data[i])
    local o = _0(fi)
    b0[o] = b0[o] + 1
    o = _1(fi)
    b1[o] = b1[o] + 1
    o = _2(fi)
    b2[o] = b2[o] + 1
  end

  local sum0  = 0
  local sum1  = 0
  local sum2  = 0
  local tsum = 0
  for i = 0, 2047, 1 do
      tsum = b0[i] + sum0
      b0[i] = sum0 - 1
      sum0 = tsum

      tsum = b1[i] + sum1
      b1[i] = sum1 - 1
      sum1 = tsum

      tsum = b2[i] + sum2
      b2[i] = sum2 - 1
      sum2 = tsum
  end

  -- adapt offsets
  for i = 0, 3*2048-1, 1 do
      b0[i] = b0[i]+start
  end

  -- sort into bins
  local tdata1 = temp1.data
  for i = start, stop, 1 do
      local fi = floatflip(data[i])
      local pos = _0(fi)
      b0[pos] = b0[pos] + 1
      tdata1[b0[pos]] = fi
  end

  local tdata2 = temp2.data
  for i = start, stop, 1 do
      local ti = tdata1[i]
      local pos = _1(ti)
      b1[pos] = b1[pos] + 1
      tdata2[b1[pos]] = ti
  end

  for i = start, stop, 1 do
      local ti = tdata2[i]
      local pos = _2(ti)
      b2[pos] = b2[pos] + 1
      data[b2[pos]] = ifloatflip(ti)
  end
  
end

local radixargsort = function(t, indices, start, stop)
  assert(t.ndim == 1)
  assert(t.strides[0] == 1)
  start = start or 0
  stop = stop or t.shape[0]-1
    
  local temp1 = Array.create({t.shape[0]}, Array.int32)
  local temp2 = Array.create({t.shape[0]}, Array.int32)
  local tind = Array.create({t.shape[0]}, Array.int32)

  local data = ffi.cast("int32_t*", t.data)

  local b0 = _radix_bins_t()
  local b1 = b0 + 2048
  local b2 = b1 + 2048
  
  for i = 0, 3*2048-1, 1 do
      b0[i] = 0
  end
  
  -- count bins
  for i = start, stop, 1 do
    local fi = floatflip(data[i])
    local o = _0(fi)
    b0[o] = b0[o] + 1
    o = _1(fi)
    b1[o] = b1[o] + 1
    o = _2(fi)
    b2[o] = b2[o] + 1
  end

  local sum0  = 0
  local sum1  = 0
  local sum2  = 0
  local tsum = 0
  for i = 0, 2047, 1 do
      tsum = b0[i] + sum0
      b0[i] = sum0 - 1
      sum0 = tsum

      tsum = b1[i] + sum1
      b1[i] = sum1 - 1
      sum1 = tsum

      tsum = b2[i] + sum2
      b2[i] = sum2 - 1
      sum2 = tsum
  end

  -- adapt offsets
  for i = 0, 3*2048-1, 1 do
      b0[i] = b0[i]+start
  end

  -- sort into bins
  local tdata1 = temp1.data
  for i = start, stop, 1 do
      local fi = floatflip(data[i])
      local pos = _0(fi)
      b0[pos] = b0[pos] + 1
      tdata1[b0[pos]] = fi
      tind.data[b0[pos]] = indices.data[i]
  end

  local tdata2 = temp2.data
  for i = start, stop, 1 do
      local ti = tdata1[i]
      local pos = _1(ti)
      b1[pos] = b1[pos] + 1
      tdata2[b1[pos]] = ti
      indices.data[b1[pos]] = tind.data[i]
  end


  for i = start, stop, 1 do
      local ti = tdata2[i]
      local pos = _2(ti)
      b2[pos] = b2[pos] + 1
      data[b2[pos]] = ifloatflip(ti)
      tind.data[b2[pos]] = indices.data[i]
  end
  
  for i = start, stop, 1 do
      indices.data[i] = tind.data[i]
  end
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
    if line2.dtype == Array.float32 and line2.strides[0] == 1 and stopi - starti > 2048 then
        radixsort(line2, starti, stopi)
    else
        quicksort(line2,_default_swap, nil, starti, stopi)
    end
    
    -- copy back
    if line2 ~= line then
      line:assign(line2)
    end
  end
  return self
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

  if copy.dtype == Array.float32 and copy.strides[0] == 1 and stop - start > 2048 then
     radixargsort(copy, indices, start, stop)
  else
    quicksort(copy,_swapper, indices.data, start, stop)
  end

  local result  = {}
  result[1] = indices
  return result
end

