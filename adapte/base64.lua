base64={}

-- 加密,编码
function base64.encode(source_str)
    return crypto.base64_encode(source_str,#source_str)
end

-- 解密,解码
function base64.decode(str64)
    return crypto.base64_decode(str64,#str64)
end

return base64
