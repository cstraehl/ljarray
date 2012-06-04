local os = require("os")
local math = require("math")

module(..., package.seeall)

-- benchmarking function
benchmark = function(f, count, name)
  local t1 = os.clock()
  for i = 1, count, 1 do
    f()
  end
  local t2 = os.clock()
  print("Benchmark "..name.." took ".. (t2-t1)/(1.0*count) .." seconds/iteration")
end

binmap = function(func, tbl1, tbl2)
  local newtbl = {}
  for i=1,#tbl1,1 do
      newtbl[i] = func(tbl1[i], tbl2[i])
  end
  return newtbl
end

copy = function(tbl)
  local newtbl = {}
  for i=1,#tbl,1 do
    newtbl[i] = tbl[i]
  end
  return newtbl
end

reduce = function(func, tbl, initial)
  local result = initial
  for i=1,#tbl,1 do
      result = func(result, tbl[i])
  end
  return result
end

cumreduce = function(func, tbl, initial)
  local newtbl = {}
  local result = initial
  for i=1,#tbl,1 do
      newtbl[i] = func(result, tbl[i])
  end
  return newtbl
end

reverse = function(tbl)
  local newtbl = {}
  local length = #tbl
  for i=1,#tbl,1 do
      newtbl[length - i + 1] = tbl[i]
  end
  return newtbl
end

-- table to formatted string
local function table_print (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
    for key, value in pairs (tt) do
      table.insert(sb, string.rep (" ", indent)) -- indent it
      if type (value) == "table" and not done [value] then
        done [value] = true
        table.insert(sb, "{\n");
        table.insert(sb, table_print (value, indent + 2, done))
        table.insert(sb, string.rep (" ", indent)) -- indent it
        table.insert(sb, "}\n");
      elseif "number" == type(key) then
        table.insert(sb, string.format("%s ", tostring(value)))
      else
        table.insert(sb, string.format(
            "%s = \"%s\"\n", tostring (key), tostring(value)))
       end
    end
    return table.concat(sb)
  else
    return tt .. "\n"
  end
end

-- pretty printing helper
function to_string( tbl )
    if  "nil"       == type( tbl ) then
        return tostring(nil)
    elseif  "table" == type( tbl ) then
        return table_print(tbl)
    elseif  "string" == type( tbl ) then
        return tbl
    else
        return tostring(tbl)
    end
end


-- helpers to protect agains undefined globals, or any globals at all
local mt = getmetatable(_G)
if mt == nil then
  mt = {}
  setmetatable(_G, mt)
end

__STRICT = true
__FORBID_GLOBALS = false
mt.__declared = {}

mt.__newindex = function (t, n, v)
  if __FORBID_GLOBALS then
    error("declared global " .. n .. " with value ".. tostring(v))
  end
  if __STRICT and not mt.__declared[n] then
    local w = debug.getinfo(2, "S").what
    if w ~= "main" and w ~= "C" then
      error("assign to undeclared variable '"..n.."'", 2)
    end
    mt.__declared[n] = true
  end
  rawset(t, n, v)
end
  
mt.__index = function (t, n)
  if not mt.__declared[n] and debug.getinfo(2, "S").what ~= "C" then
    error("variable '"..n.."' is not declared", 2)
  end
  return rawget(t, n)
end

function global(...)
   for _, v in ipairs{...} do mt.__declared[v] = true end
end
