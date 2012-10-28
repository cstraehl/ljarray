--  array_iterators.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isarray = helpers.isarray


local _pos_it = function(state, pos)
    local self = state.self
    local dim = state.ldim

    pos[dim] = pos[dim] + 1

    while pos[dim] >= self.shape[dim] do
        pos[dim] = 0

        dim = dim - 1
        if dim < 0 then
            return nil
        end
        pos[dim] = pos[dim] + 1
    end

    return pos
end

--- iterator that yields the coordinates of an array
-- @returns pos a zero based coordinate
function Array.coordinates(self)
  local pos = {}
  local ldim = 0
  for d = 0, self.ndim-1,1 do
      pos[d] = 0
      if self.shape[d] > 1 then
          ldim = d
      end
  end
  pos[ldim] = -1
  local state = { self = self, ldim = ldim}
  return _pos_it, state, pos
end


local _values_it = function(state, value)
    local self = state.self
    local ldim = state.ldim
    local pos = state.pos

    pos[ldim] = pos[ldim] + 1
    state.offset = state.offset + self.strides[ldim]

    if pos[ldim] >= self.shape[ldim] then
        local dim = ldim
        while pos[dim] >= self.shape[dim] do
            pos[dim] = 0
            state.offset = state.offset - self.shape[dim] * self.strides[dim]

            dim = dim - 1
            if dim < 0 then
                return nil
            end
            pos[dim] = pos[dim] + 1
            state.offset = state.offset + self.strides[dim]
        end
    end

    return self.data[state.offset]
end

--- iterator that yields the values of an array
-- @returns val an array element
function Array.values(self)
  local pos = {}
  local ldim = 0
  for d = 0, self.ndim-1,1 do
      pos[d] = 0
      if self.shape[d] > 1 then
          ldim = d
      end
  end
  pos[ldim] = -1
  local state = { self = self, ldim = ldim, offset = -self.strides[ldim], pos = pos}
  return _values_it, state, 0
end


local _pairs_it = function(state, pos)
    local self = state.self
    local ldim = state.ldim

    pos[ldim] = pos[ldim] + 1
    state.offset = state.offset + self.strides[ldim]

    local dim = ldim
    while pos[dim] >= self.shape[dim] do
        pos[dim] = 0
        state.offset = state.offset - self.shape[dim] * self.strides[dim]

        dim = dim - 1
        if dim < 0 then
            return nil
        end
        pos[dim] = pos[dim] + 1
        state.offset = state.offset + self.strides[dim]
    end

    return pos, self.data[state.offset]
end

--- iterator that yields the coordinates and values of an array
-- @returns pos an zero based table
-- @returns val an array element at coordinate pos
function Array.pairs(self)
  local pos = {}
  local ldim = 0
  for d = 0, self.ndim-1,1 do
      pos[d] = 0
      if self.shape[d] > 1 then
          ldim = d
      end
  end
  pos[ldim] = -1
  local state = { self = self, ldim = ldim, offset = -self.strides[ldim]}
  return _pairs_it, state, pos, 0
end
