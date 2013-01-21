---- implementation of splay trees for luajit
--


-- extend package.path with path of this .lua file:local filepath = debug.getinfo(1).source:match("@(.*)$") 
local math = require("math") 
local ffi = require("ffi")
local bitop = require("bit")
local jit = require("jit")

require("luarocks.loader")
local array = require("ljarray.array")
local helpers = require("ljarray.helpers")
local logger = require("ljarray.log")


ffi.cdef([[
  typedef struct {
    double key;
    int left;
    int right;
    int next;
    int prev;
    int used;
  } splay_node;
]])

local Splay_node = ffi.typeof("splay_node")

array.register_dtype("splay_node", Splay_node)

local SH = {}
SH.__index = SH

local _default_comp = function(a,b)
  return a > b
end

SH.create = function(comp)
  local st = {}
  setmetatable(st,SH)
  st.comp = comp or _default_comp
  st.max_size = 0
  st.free_list = array.create({1}, array.int32)
  st.free_pos = -1
  st.nodes = array.create({1}, Splay_node)
  st.root = -1
  st:_resize(2048)
  return st
end

SH.key = function(self, n)
    return self.nodes.data[n].key
end


SH.find_key = function(self, k)
    return self:_splay_key(k,self.root)
end

SH.insert_key = function(self, v)
  local new = self:_create_tree()
  local t = self.root

  self.nodes.data[new].key = v
  if t == -1 then
    self.root = new
    return new
  end

  t = self:_splay_key(v,t)
  local nodes = self.nodes.data
  local t_node = nodes[t]

  if self.comp(v , t_node.key) then
    nodes[new].left = t_node.left
    nodes[new].right = t
    t_node.left = -1
  elseif self.comp(t_node.key, v) then
    nodes[new].right = t_node.right
    nodes[new].left = t
    t_node.right = -1
  else -- same key, prepend to list
    if t_node.next ~= -1 then
        nodes[t_node.next].prev = new
    end
    nodes[new].next = t_node.next
    t_node.next = new
    return new
  end
  self.root = new
  return new
end


SH.remove_key = function(self, v)
  local t = self.root
  if t == -1 then
    return
  end
  t = self:_splay_key(v,t)
  local t_node = self.nodes.data[t]
  if v == t_node.key then
    if t_node.next == -1 then
        local x
        -- just a single node with that key
        if t_node.left == -1 then
          x = t_node.right
        else
          x = self:_splay_key(v, t_node.left)
          self.nodes.data[x].right = t_node.right
        end
        self.root = x
    else
        -- more nodes with that key exist
        -- -> replace first one with next
        local nodes = self.nodes.data
        self.root = t_node.next
        nodes[t_node.next].prev = -1
        nodes[t_node.next].left = t_node.left
        nodes[t_node.next].right= t_node.right
    end
    self:_delete_tree(t)
    return t
  end
  -- no node with that key found..
  self.root = t
  return
end

SH.remove_node = function(self, n)
  local nodes = self.nodes.data
  local node = nodes[n]

  local t = self.root
  if t == -1 or node.used == 0 then
    return
  end
  if node.prev == -1 then
      -- first node with that key
      -- -> call normal remove_key
      local del =  self:remove_key(node.key)
      return del
  else
      -- not first node with that key
      -- -> remove from doubly linked list
      nodes[node.prev].next = node.next
      if node.next ~= -1 then
          nodes[node.next].prev = node.prev
      end
      self:_delete_tree(n)
      return n
  end
end

SH._splay_key = function(self, v, t)
  if t == -1 then
    return t
  end

  local y
  local N = self:_create_tree()
  local l = N
  local r = N
  local nodes = self.nodes.data

  while true do
    local node = nodes[t]
    if self.comp(v, node.key) then --smaller then node
      if nodes[t].left ~= -1 and self.comp(v, nodes[nodes[t].left].key) then --smaller then left
        y = node.left
        node.left = nodes[y].right
        nodes[y].right = t
        t = y
      end
      if nodes[t].left == -1 then
        break
      end
      nodes[r].left = t
      r = t
      t = nodes[t].left
    elseif self.comp(node.key, v) then
      if node.right ~= -1 and self.comp(nodes[node.right].key, v) then -- smaller then right
        y = node.right
        node.right = nodes[y].left
        nodes[y].left = t
        t = y
      end
      if nodes[t].right == -1 then
        break
      end
      nodes[l].right = t
      l = t
      t = nodes[t].right
    else
      break
    end
  end

  nodes[l].right = nodes[t].left
  nodes[r].left = nodes[t].right
  nodes[t].left = nodes[N].right
  nodes[t].right = nodes[N].left

  self:_delete_tree(N)
  self.root = t
  return t
end


SH._create_tree = function(self)
  if self.free_pos < 0 then
    self:_resize(self.max_size * 2)
  end
  local fn = self.free_list.data[self.free_pos]
  self.free_pos = self.free_pos - 1
  local node = self.nodes.data[fn]
  node.left = -1
  node.right = -1
  node.next = -1
  node.prev = -1
  node.used = 1
  return fn
end

SH._delete_tree = function(self, tn)
  assert(self.free_pos < self.max_size-1)
  self.free_pos = self.free_pos + 1
  self.free_list.data[self.free_pos] = tn
  self.nodes.data[tn].used = 0
end


SH._resize = function(self, size)
  self.free_list:resize({size+1})
  self.nodes:resize({size+1})
  for i = self.max_size, size-1, 1 do
      self.nodes.data[i].used = 0
  end

  for i = 0, size - self.max_size - 1,1 do
    self.free_list.data[i] = size - i - 1
  end
  self.free_pos = size - self.max_size - 1
  self.max_size = size
end

return SH

-- local testsize = 1e6
-- --local values = array.randint(0,1e6, {testsize})
-- local values = array.rand({testsize})
-- local st = SH.create( function(a,b) return a < b end )
-- 
-- print("ADDING...")
-- for i = 0, testsize-1 do
--   local val =  values.data[i]
--   st:insert_key(val)
-- end
-- 
-- 
-- print("removed: ", st:remove_node(0))
-- print("removed: ", st:remove_node(0))
-- 
-- print("REMOVING...")
-- local last
-- for i = 1,testsize-1,1 do
--   local top = st:find_key(0) -- search for smalles element
--   if top ~= -1 then
--       local key = st.nodes.data[top].key
--       --print("removing ", top, key)
--       st:remove_node(i)
--       --local rem = st:remove_key(key)
--       -- assert(rem == top)
--       -- if last ~= nil then
--       --   assert(key >= last)
--       -- end
--       last = key
--   else
--       print("heap empty : ", i)
--       break
--   end
-- end

