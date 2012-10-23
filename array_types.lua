local ffi = require("ffi")

ffi.cdef[[
void *malloc(size_t size);
void free(void *ptr);
]]

local dtypes = {"int8_t"
                ,"int16_t"
                ,"int32_t"
                ,"int64_t"
                ,"uint8_t"
                ,"uint16_t"
                ,"uint32_t"
                ,"uint64_t"
                ,"float"
                ,"double"
                ,"void *"}

Array.dtype_vla = {}
Array.dtype_pointer = {}
Array.dtype_size = {}
Array.dtype_string = {}

Array.register_dtype = function(dts, dtype)
    if Array[dts] ~= nil then
        return
    end
    Array[dts] = dtype
    Array.dtype_size[dtype] = ffi.sizeof(dtype)
    Array.dtype_vla[dtype] = ffi.typeof(dts .. "[?]")
    Array.dtype_pointer[dtype] = ffi.typeof(dts .. " *")
    Array.dtype_string[dtype] = dts
end

for i,dtsf in ipairs(dtypes) do
    local names = {dtsf}
    if string.sub(dtsf,-2) == "_t" then
        names = {string.sub(dtsf,1,#dtsf-2), dtsf}
    end
    for j,dts in ipairs(names) do
        local dtype = ffi.typeof(dtsf) 
        Array.register_dtype(dtsf, dtype)
        Array[dts] = Array[dtsf]
    end
end

Array.float32 = Array.float
Array.float64 = Array.double

-- -- some VLA ffi types for arrays
-- Array.element_type = {}
-- 
-- Array.int8 = ffi.typeof("int8_t[?]");
-- Array.element_type[Array.int8] = ffi.typeof("int8_t")
-- 
-- Array.int16 = ffi.typeof("int16_t[?]");
-- Array.element_type[Array.int16] = ffi.typeof("int16_t")
-- 
-- Array.int32 = ffi.typeof("int32_t[?]");
-- Array.element_type[Array.int32] = ffi.typeof("int32_t")
-- 
-- Array.int64 = ffi.typeof("int64_t[?]");
-- Array.element_type[Array.int64] = ffi.typeof("int64_t")
-- 
-- Array.uint8 = ffi.typeof("uint8_t[?]");
-- Array.element_type[Array.uint8] = ffi.typeof("uint8_t")
-- 
-- Array.uint16 = ffi.typeof("uint16_t[?]");
-- Array.element_type[Array.uint16] = ffi.typeof("uint16_t")
-- 
-- Array.uint32 = ffi.typeof("uint32_t[?]");
-- Array.element_type[Array.uint32] = ffi.typeof("uint32_t")
-- 
-- Array.uint64 = ffi.typeof("uint64_t[?]");
-- Array.element_type[Array.uint64] = ffi.typeof("uint64_t")
-- 
-- Array.float32 = ffi.typeof("float[?]");
-- Array.element_type[Array.float32] = ffi.typeof("float")
-- 
-- Array.float64 = ffi.typeof("double[?]");
-- Array.element_type[Array.float64] = ffi.typeof("double")
-- 
-- Array.pointer = ffi.typeof("void *");
-- Array.element_type[Array.pointer] = ffi.typeof("void *")
-- 
-- -- pointer types
-- local cpointer = {}
-- cpointer.int8 = ffi.typeof("int8_t*");
-- cpointer[Array.int8] = cpointer.int8
-- 
-- cpointer.int16 = ffi.typeof("int16_t*");
-- cpointer[Array.int16] = cpointer.int16
-- 
-- cpointer.int32 = ffi.typeof("int32_t*");
-- cpointer[Array.int32] = cpointer.int32
-- 
-- cpointer.int64 = ffi.typeof("int64_t*");
-- cpointer[Array.int64] = cpointer.int64
-- 
-- cpointer.uint8 = ffi.typeof("uint8_t*");
-- cpointer[Array.uint8] = cpointer.uint8
-- 
-- cpointer.uint16 = ffi.typeof("uint16_t*");
-- cpointer[Array.uint16] = cpointer.uint16
-- 
-- cpointer.uint32 = ffi.typeof("uint32_t*");
-- cpointer[Array.uint32] = cpointer.uint32
-- 
-- cpointer.uint64 = ffi.typeof("uint64_t*");
-- cpointer[Array.uint64] = cpointer.uint64
-- 
-- cpointer.float32 = ffi.typeof("float*");
-- cpointer[Array.float32] = cpointer.float32
-- 
-- cpointer.float64 = ffi.typeof("double*");
-- cpointer[Array.float64] = cpointer.float64
-- 
-- Array.cpointer = cpointer
-- 
-- Array.element_type_size = {}
-- Array.dtype_string_to_dtype = {}
-- Array.cpointer_string_to_dtype = {}
-- Array.size_of_dtype = {}
-- for k,v in pairs(Array.element_type) do
--   Array.element_type_size[v] = ffi.sizeof(v)
--   Array.cpointer[v] = Array.cpointer[k]
--   Array.dtype_string_to_dtype[tostring(k)] = k
--   Array.cpointer_string_to_dtype[tostring(cpointer)] = k
--   Array.size_of_dtype[k] = ffi.sizeof(Array.element_type[k])
-- end
