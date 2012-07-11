local os = require("os")

module(..., package.seeall)

_indent = 0
_prefixes = {} -- holds string prefixes for the indent levels
_start_times = {} -- stores start time of indent levels
_information = {} -- holds information about last closed indent level
_prefix = ""
_messages = {}
_messages[0] = {}

console = {} -- which log types shoudl be printed the console ?
console.warn = 1
store = {} -- which log types should be logged ?
store.warn = 1

-- printf helper that respects indentation
function printf(s,...)
  local spaces = string.rep(" ", _indent) .. _prefix .. ": "
  return io.write(string.format("%s%s",spaces, string.format(s,...)))
end -- function

-- format helper that respects indentation
function format(s,...)
  local spaces = string.rep(" ", _indent) .. _prefix ..": "
  return string.format("%s%s",spaces, string.format(s,...))
end -- function


-- loggin helper
function log(level, s, ...)
  if store.level then
    _messages[_indent].level = _messages[_indent].level or {}
    table.insert(_messages[_indent].level, string.format(s,...))
  end
  if console[level] then
    printf(" %s: %s", level, string.format(s, ...))
  end
end

function indent(level, prefix)
  _prefixes[_indent] = _prefix
  if type(level) == "string" then
    prefix = level
    level = nil
  end
  level = level or 2
  _prefix = prefix
  _indent = _indent + level
  _start_times[_indent] = os.time()
  _messages[_indent] = {}
end



function unindent(level)
  local stop_time = os.time()
  local information = {}
  -- store information about current indent level
  information.prefix = _prefix
  information.indent = _indent
  information.start = _start_times[_indent]
  information.stop = stop_time
  information.time = information.stop - information.start
  information.messages = _messages[_indent]
  _prefixes[_indent] = _prefix -- store current prefix

  level = level or 2
  _indent = _indent - level
  if _indent < 0 then
    _indent = 0
  end
  _prefix = _prefixes[_indent]
  return information
end

function print_runtime(info)
  printf(" - %s - took %fs.\n", info.prefix, info.time)
end

function print_log(level)
  for k,s in pairs(_messages[_indent].level) do
    printf(" - %s - %s: %s", _information.prefix, level, s)
  end
end

indented = function(f, ...) 
  indent()
  f(...)
  unindent()
end
