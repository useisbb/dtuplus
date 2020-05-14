----------------------[MODBUS read data]--------------------------
local function read_multi_register(obj,start,bytes_len)
    return 0x03,start,bytes_len
end

----------------------[MODBUS write data]--------------------------
local function write_multi_register(obj,start,data,bytes_len)
    return 0x10,start,bytes_len/2,bytes_len,data
end


local function response_distance(raw_data, len)
    obj={}
    local _, data= bunpack(raw_data,">i")
    obj.weiyi = data * 0.001
    return obj
end


----------------------[test control demo]--------------------------
local function control_test_demo(obj)
    if obj and obj.value and  obj.value2 then
        local data = bpack(">S>S",obj.value,obj.value2)
        return write_multi_register(obj,0x0001,data,#data)
    end
end

local function response_test_demo(raw_data, len)
    local obj={}
    obj.error = 0
    return obj
end


global_identifier_func_tab = {
    {
        identifier="weiyishangbao",
        create_bin_func=read_multi_register,
        create_bin_args={0x0000,2},
        parser_bin_func=response_distance
    },
    {
        identifier="control_test_demo",
        create_bin_func=control_test_demo,
        create_bin_args={nil,nil},
        parser_bin_func=response_test_demo
    }
}


function protocol_encode(json_str, len)
    local err_code=0

    --取出入参--
    local obj=cjson.decode(json_str)
    local id=obj.identifier
    local addr=tonumber(obj.term_addr,16)
    --编码--
    -- print(json_str)
    if id == "null" then
        return 0, "", 0
    end
    local raw_data=nil
    for i,v in pairs(global_identifier_func_tab) do
        if v.identifier == id then
            local call_func = v.create_bin_func
            local func,start,len,data_len,data = call_func(obj,v.create_bin_args[1],v.create_bin_args[2])
            local bin=nil
            if not data then
                raw_data = bpack("CC>S>S",addr,func,start,len)
            else
                raw_data = bpack("CC>S>SC",addr,func,start,len,data_len)
                for i = 1, #data do raw_data = raw_data .. bpack("c",data:byte(i)) end
            end
            raw_data = raw_data .. bpack(">S",dyutils.CRC16(raw_data,#raw_data))

            local t_str=''
            for i=1, #raw_data do
                t_str=t_str .. (string.format("%02X", string.byte(string.sub(raw_data, i, i))))
            end

            print(t_str,#t_str)
            return err_code, t_str, #t_str
        end
    end
    return -1, nil, 0
end

function protocol_decode(input_str, len)
    local err_code=0

    -- print(input_str)

    --取出入参--
    local obj={}
    local input_obj=cjson.decode(input_str)
    local bin_str=input_obj.raw_data
    local id=input_obj.identifier
    --入参中的raw_data的二进制转换--
    if not bin_str or #bin_str < 6 then
        print(string.format( "Input args failed,args:%s",input_str))
        return nil
    end
    local t_str=''
    for i=1,#bin_str,2 do
        t_str=t_str .. string.char(tonumber(string.sub(bin_str, i, i+1),16))
    end

    raw_data=t_str
    local crc = dyutils.CRC16(raw_data,#raw_data - 2)
    _,crc_pack = bunpack(string.sub(raw_data,#raw_data - 1),">S")

    if (crc ~= crc_pack) then
        print(string.format( "Data crc check failed cal:%04X packet:%04X",crc,crc_pack))
        return nil
    end
    _,addr,func = bunpack(raw_data,"CC")

    local call_func = v.parser_bin_func
    local data,data_len = nil,0
    if func == 0x03 then data_len = #raw_data - 4 - 1 data = string.sub(raw_data,4,-3)
    elseif func == 0x10  then data_len = 0 data = nil
    else
        print(string.format( "unknow function code %02X",func))
        return nil
    end
    local json_obj = response_distance(raw_data, len)
    json_obj.identifier="weiyishangbao"                             -- 返回调用标识
    json_obj.term_addr=string.format( "%02X",addr)
    local json_str=cjson.encode(json_obj)
    print(err_code, json_str, #json_str)
    return err_code,json_str,#json_str

end

modules={}
function modules.protocol_decode(...)  return protocol_decode(...) end
function modules.protocol_encode(...)  return protocol_encode(...) end
return modules
