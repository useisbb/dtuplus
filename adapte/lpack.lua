require "pack"

pack={}

function pack.pack(...)
    return string.pack(...)
end

function pack.unpack(...)
    return string.unpack(...)
end

return pack
