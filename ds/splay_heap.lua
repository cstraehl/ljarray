---- implementation of splay trees for luajit
--


-- extend package.path with path of this .lua file:local filepath = debug.getinfo(1).source:match("@(.*)$") 
local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local jit = require("jit")

require("luarocks.loader")
local array = require("ljarray.array")

local splay_heap = require("ljarray.ds.splay_heap_raw")

local _default_comp = function(a,b)
  return a > b
end

local SH = {}
SH.__index = SH

SH.create = function(comp) 
    local self = {}
    setmetatable(self, SH)
    comp = comp or _default_comp
    self.heap = splay_heap.create(comp)
    if comp(1,0) then
        self.smallest = 1e99999999999999
    else
        self.smallest = -1e9999999999999
    end
    self.element_to_node = {}
    self.node_to_element = {}
    return self
end


SH.insert = function(self, element, key)
    assert(self.element_to_node[element] == nil, "element already in heap !")
    local node = self.heap:insert_key(key)
    self.element_to_node[element] = node
    self.node_to_element[node] = element
end

SH.remove = function(self, element)
    local node = self.element_to_node[element]
    assert(node ~= nil, "element not in heap !")
    self.heap:remove_node(node)
    self.element_to_node[element] = nil
    self.node_to_element[node] = nil
end

SH.find = function(self, key)
    local node = self.heap:find_key(key)
    return self.node_to_element[node]
end

SH.top = function(self)
    local node = self.heap:find_key(self.smallest)
    return self.node_to_element[node]
end

SH.key = function(self, element)
    local node = self.element_to_node[element]
    assert(node ~= nil, "element not in heap!")
    return self.heap:key(node)
end

SH.update_key = function(self, element, newkey)
    local node = self.element_to_node[element]
    assert(node ~= nil, "element not in heap !")
    self.heap:remove_node(node)
    local node_new = self.heap:insert_key(newkey)
    assert(node == node_new)
end

return SH
