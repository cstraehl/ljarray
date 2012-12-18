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
Array._arr_types = {}

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
