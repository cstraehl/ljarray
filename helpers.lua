local os = require("os")
local math = require("math")

module(..., package.seeall)

operator = {
     mod = math.mod;
     pow = math.pow;
     add = function(n,m) return n + m end;
     sub = function(n,m) return n - m end;
     mul = function(n,m) return n * m end;
     div = function(n,m) return n / m end;
     gt  = function(n,m) return n > m end;
     lt  = function(n,m) return n < m end;
     eq  = function(n,m) return n == m end;
     le  = function(n,m) return n <= m end;
     ge  = function(n,m) return n >= m end;
     ne  = function(n,m) return n ~= m end;
     assign  = function(a,b) return b end; 
 }

isarray = function(a)
  if type(a) == "table" and (a.__metatable == Array or a._type == "array") then
    return true
  else
    return false
  end
end

zeros = function(length)
  local temp = {}
  for i = 0,length-1,1 do
    temp[i] = 0
  end
  return temp
end

equal = function(tbl1, tbl2)
  local answer = true
  for i=0,#tbl1 do
    if tbl1[i] ~= tbl2[i] then
      answer = false
      break
    end
  end
  return answer
end


-- benchmarking function
benchmark = function(f, count, name)
  local t1 = os.clock()
  for i = 1, count, 1 do
    f()
  end
  local t2 = os.clock()
  print("Benchmark "..name.." took ".. (t2-t1)/(1.0*count) .." seconds/iteration")
end

zerobased = function(tbl)
  local result = tbl
  if tbl[0] == nil then
    result = {}
    for i=1,#tbl,1 do
      result[i-1] = tbl[i]
    end
  end
  return result
end

binmap = function(func, tbl1, tbl2)
  local newtbl = {}
  local start = 0
  local stop = #tbl1
  assert(tbl1[0] ~= nil)
  if tbl1[0] == nil then
    assert(tbl2[0] == nil)
    start = 1
    stop = #tbl1
  end
  for i=start,stop,1 do
      newtbl[i] = func(tbl1[i], tbl2[i])
  end
  return newtbl
end

copy = function(tbl)
  local newtbl = {}
  local start = 0
  local stop = #tbl
  assert(tbl[0] ~= nil)
  if tbl[0] == nil then
    start = 1
    stop = #tbl 
  end
  for i=start,stop,1 do
    newtbl[i] = tbl[i]
  end
  return newtbl
end

reduce = function(func, tbl, initial)
  local result = initial
  local start = 0
  local stop = #tbl
  assert(tbl[0] ~= nil)
  if tbl[0] == nil then
    start = 1
    stop = #tbl
  end
  for i=start,stop,1 do
      result = func(result, tbl[i])
  end
  return result
end

cumreduce = function(func, tbl, initial)
  local newtbl = {}
  local result = initial
  local start = 0
  local stop = #tbl+1
  assert(tbl[0] ~= nil)
  if tbl[0] == nil then
    start = 1
    stop = #tbl
  end
  for i=start,stop,1 do
      newtbl[i] = func(result, tbl[i])
  end
  return newtbl
end

reverse = function(tbl)
  local newtbl = {}
  local length = #tbl 
  local start = 0
  local stop = #tbl
  assert(tbl[0] ~= nil)
  if tbl[0] == nil then
    start = 1
    stop = #tbl 
    length = #tbl + 1
  end
  for i=start,stop,1 do
      newtbl[length - i] = tbl[i]
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

-- printf helper
function printf(s,...)
 return io.write(s:format(...))
end -- function


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
