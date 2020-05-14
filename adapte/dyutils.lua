require("bit")
dyutils = {}
-- Lua 5.1+ base64 v3.0 (c) 2009 by Alex Kloss <alexthkloss@web.de>
-- licensed under the terms of the LGPL2

-- character table string
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- translate string of hex to data
function dyutils.hex_str_to_bin(hex_str)
	local t_str=''

    for i=1, string.len(hex_str),2 do
        t_str=t_str .. string.char(tonumber(string.sub(hex_str, i, i+1),16))
    end
    return t_str, string.len(t_str)
end

-- translate data to hex str
function dyutils.bin_str_to_hex(bin_str)
	local t_str = ''
	local charcode
	local hexstr

	for i = 1, string.len(bin_str) do
		local charcode = tonumber(string.byte(bin_str, i, i))
		local hexstr = string.format("%02X", charcode)
		t_str = t_str .. hexstr
    end

    return t_str, string.len(t_str)
end

-- 字符串分割
function dyutils.split(input, delimiter)
    local arr = {}
    string.gsub(input, '[^' .. delimiter ..']+', function(w) table.insert(arr, w) end)
    return arr
end

-- 查看某值是否为表tbl中的key值
function table.kIn(tbl, key)
    if tbl == nil then
        return false
    end
    for k, v in pairs(tbl) do
        if k == key then
            return true
        end
    end
    return false
end


-- 查看某值是否为表tbl中的value值
function table.vIn(tbl, value)
    if tbl == nil then
        return false
    end

    for k, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- encoding
function dyutils.enc(data)
    return ((data:gsub('.', function(x)
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- decoding
function dyutils.dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(7-i) or 0) end
        return string.char(c)
    end))
end


function dyutils.CRC16(modbusdata, length)
    local i=0; local j=0; local crc=0xFFFF; local k=1; local k=1; local l=1;

    for k=1, length do
        crc = bit.bxor(crc, string.byte(string.sub(modbusdata,k,k)))
        for l=1, 8 do
            if bit.band(crc, 1) == 1 then
                crc = bit.rshift(crc, 1)
                crc = bit.bxor(crc, 0xa001)
            else
                crc = bit.rshift(crc, 1)
            end
        end
    end

    return bit.band(bit.lshift(crc,8),0xFFFF)+bit.rshift(crc,8)
end

function dyutils.CalculateXorCrc(arr_buff, len)
    local lastValue = 0
    local shiftBitNum = {24, 16, 8}
    local fractionalData = bit.band(len, 0x3)
    local crc = 0
    local int_len = math.modf(len/4)
    local k = 1
    local i = 1

    for k=0, int_len-1 do
        local sub =  string.sub(arr_buff,k*4 + 1, k*4 + 4)
        _, t = bunpack(sub, "I")
        crc = bit.bxor(crc, t)
    end

    if (fractionalData ~= 0) then
        for i=1, fractionalData do
            lastValue = bit.bor(lastValue, bit.lshift(string.byte(string.sub(arr_buff,len-fractionalData+i,len-fractionalData+i)), shiftBitNum[i]))
        end
        crc = bit.bxor(crc, lastValue)
    end

    return crc;
end

function dyutils.packIEEE754(number)
    if number == 0 then
        return string.char(0x00, 0x00, 0x00, 0x00)
    elseif number ~= number then
        return string.char(0xFF, 0xFF, 0xFF, 0xFF)
    else
        local sign = 0x00
        if number < 0 then
            sign = 0x80
            number = -number
        end
        local mantissa, exponent = math.frexp(number)
        exponent = exponent + 0x7F
        if exponent <= 0 then
            mantissa = math.ldexp(mantissa, exponent - 1)
            exponent = 0
        elseif exponent > 0 then
            if exponent >= 0xFF then
                return string.char(sign + 0x7F, 0x80, 0x00, 0x00)
            elseif exponent == 1 then
                exponent = 0
            else
                mantissa = mantissa * 2 - 1
                exponent = exponent - 1
            end
        end
        mantissa = math.floor(math.ldexp(mantissa, 23) + 0.5)
        return string.char(
                sign + math.floor(exponent / 2),
                (exponent % 2) * 0x80 + math.floor(mantissa / 0x10000),
                math.floor(mantissa / 0x100) % 0x100,
                mantissa % 0x100)
    end
end
function dyutils.unpackIEEE754(packed)
    local b1, b2, b3, b4 = string.byte(packed, 1, 4)
    local exponent = (b1 % 0x80) * 0x02 + math.floor(b2 / 0x80)
    local mantissa = math.ldexp(((b2 % 0x80) * 0x100 + b3) * 0x100 + b4, -23)
    if exponent == 0xFF then
        if mantissa > 0 then
            return 0 / 0
        else
            mantissa = math.huge
            exponent = 0x7F
        end
    elseif exponent > 0 then
        mantissa = mantissa + 1
    else
        exponent = exponent + 1
    end
    if b1 >= 0x80 then
        mantissa = -mantissa
    end
    local tmp=math.ldexp(mantissa, exponent - 0x7F)
    return tmp-tmp%0.000001
end

return dyutils
