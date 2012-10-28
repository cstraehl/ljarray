--  array_map.lua - a tiny multidimensional array library for luajit
--  Copyright Christoph Straehle (cstraehle@gmail.com)
--  License: BSD

local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local helpers = require("helpers")
local operator = helpers.operator
local isarray = helpers.isarray


--- iterates over an array and calls a function for each value
--
--  @param f function to call. the function receives the
--            value of the array element as first argument
--            and optionally table with the coordinate of
--            the current element
--            the return value of the function for each
--            element is stored in the array.
--  @param call_with_position if true, the funciton f will be
--            called with the currents array element position
--
Array.mapInplace = function(self,f, call_with_position)
    local pos = {}
    local ldim = 0
    for d = 0, self.ndim-1,1 do
        pos[d] = 0
        if self.shape[d] > 1 then
            ldim = d
        end
    end

    local finished = false
    local offset = 0

    while true do
        if call_with_position == false then
            for toffset = offset, offset + self.shape[ldim]*self.strides[ldim]-1,self.strides[ldim] do
                self.data[toffset] = f(self.data[toffset])
            end
        else
            for toffset = offset, offset + self.shape[ldim]*self.strides[ldim]-1,self.strides[ldim] do
                self.data[toffset] = f(self.data[toffset],pos)
                pos[ldim] = pos[ldim] + 1
            end
            pos[ldim] = 0
        end

        local dim = ldim - 1
        if dim < 0 then
            return
        end

        pos[dim] = pos[dim] + 1
        offset = offset + self.strides[dim]

        while pos[dim] >= self.shape[dim] do
            pos[dim] = 0
            offset = offset - self.shape[dim] * self.strides[dim]

            dim = dim - 1
            if dim < 0 then
                return
            end
            pos[dim] = pos[dim] + 1
            offset = offset + self.strides[dim]
        end
    end
end




--- iterates jointly over two arrays and calls a function with  the two values of the arrays at the current coordinate
--
-- @param other the other array, must have the same dimension and shape
-- @param f function to call. the function receives the
--            value of the array element as first argument
--            and the value of the second arrays as second arguemnt.
--            third argument is optionally a table with the coordinate of
--            the current elements.
--            The return value of f for each element pair
--            is stored in the first array.
-- @param call_with_position optional, if true, the funciton f will be
--            called with the currents array element position
function Array.mapBinaryInplace(self,other,f, call_with_position)
    local pos = {}
    local ldim = 0
    for d = 0, self.ndim-1,1 do
        pos[d] = 0
        if self.shape[d] > 1 then
            ldim = d
        end
    end

    local finished = false
    local offset = 0
    local offset2 = 0

    while true do
        if call_with_position == false then
            for toffset = offset, offset + self.shape[ldim]*self.strides[ldim]-1,self.strides[ldim] do
                self.data[toffset] = f(self.data[toffset],other.data[offset2])
                offset2 = offset2 + other.strides[ldim]
            end
        else
            for toffset = offset, offset + self.shape[ldim]*self.strides[ldim]-1,self.strides[ldim] do
                self.data[toffset] = f(self.data[toffset],other.data[offset2],pos)
                pos[ldim] = pos[ldim] + 1
                offset2 = offset2 + other.strides[ldim]
            end
            pos[ldim] = 0
        end

        local dim = ldim - 1
        if dim < 0 then
            return
        end

        offset2 = offset2 - self.shape[ldim]*other.strides[ldim]

        pos[dim] = pos[dim] + 1
        offset = offset + self.strides[dim]
        offset2 = offset2 + other.strides[dim]

        while pos[dim] >= self.shape[dim] do
            pos[dim] = 0
            offset = offset - self.shape[dim] * self.strides[dim]
            offset2 = offset2 - self.shape[dim] * other.strides[dim]

            dim = dim - 1
            if dim < 0 then
                return
            end
            pos[dim] = pos[dim] + 1
            offset = offset + self.strides[dim]
            offset2 = offset2 + other.strides[dim]
        end
    end
end



--- iterates jointly over three arrays and calls a function with the three values of the arrays at the current coordinate
-- 
-- @param other the second array, must have the same dimension and shape
-- @param other2 the third array, must have the same dimension and shape
-- @param f the function to call. the function receives the
--            value of the array element as first argument
--            and the value of the second arrays as second arguemnt
--            and the value of the third array as third argument.
--            third argument is optionally a table with the coordinate of
--            the current elements.
--            The return value of f for each element triple is stored
--            in the first array.
-- @param call_with_position optional, if true, the funciton f will be
--            called with the currents array element position
function Array.mapTenaryInplace(self,other, other2,f, call_with_position)
    local pos = {}
    local ldim = 0
    for d = 0, self.ndim-1,1 do
        pos[d] = 0
        if self.shape[d] > 1 then
            ldim = d
        end
    end

    local finished = false
    local offset = 0
    local offset2 = 0
    local offset3 = 0

    while finished == false do

        if call_with_position == false then
            for toffset = offset, offset + self.shape[ldim]*self.strides[ldim]-1,self.strides[ldim] do
                self.data[toffset] = f(self.data[toffset],other.data[offset2],other2.data[offset3])
                offset2 = offset2 + other.strides[ldim]
                offset3 = offset3 + other2.strides[ldim]
            end
        else
            for toffset = offset, offset + self.shape[ldim]*self.strides[ldim]-1,self.strides[ldim] do
                self.data[toffset] = f(self.data[toffset],other.data[offset2],other2.data[offset3],pos)
                pos[ldim] = pos[ldim] + 1
                offset2 = offset2 + other.strides[ldim]
                offset3 = offset3 + other2.strides[ldim]
            end
            pos[ldim] = 0
        end

        local dim = ldim - 1
        if dim < 0 then
            break
        end
        
        offset2 = offset2 - self.shape[ldim]*other.strides[ldim]
        offset3 = offset3 - self.shape[ldim]*other2.strides[ldim]

        pos[dim] = pos[dim] + 1
        offset = offset + self.strides[dim]
        offset2 = offset2 + other.strides[dim]
        offset3 = offset3 + other2.strides[dim]

        while pos[dim] >= self.shape[dim] do
            pos[dim] = 0
            offset = offset - self.shape[dim] * self.strides[dim]
            offset2 = offset2 - self.shape[dim] * other.strides[dim]
            offset3 = offset3 - self.shape[dim] * other2.strides[dim]

            dim = dim - 1
            if dim < 0 then
                finished = true
                break
            end
            pos[dim] = pos[dim] + 1
            offset = offset + self.strides[dim]
            offset2 = offset2 + other.strides[dim]
            offset3 = offset3 + other2.strides[dim]
        end
    end
end
