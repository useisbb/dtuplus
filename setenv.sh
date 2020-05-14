LUA_VER5_1=`dpkg -s lua5.1 | grep 'installed'`
if [ -z "$LUA_VER5_1" ];
then
        echo "You need install lua5.1,run sudo apt install lua5.1"
        exit 0
fi

LUA_VER5_2=`dpkg -s lua5.2 | grep 'installed'`
LUA_VER5_3=`dpkg -s lua5.3 | grep 'installed'`
if [ -n "$LUA_VER5_2" -o  -n "$LUA_VER5_3" ];
then
        echo "You need remove lua5.2 or lua5.3,run sudo apt remove lua5.2 or lua5.3"
        exit 0
fi



DEPENDS="chronos elscheduler lpack lsocket lua-fs-module lua-cjson luabitop luars232 "
for k in ${DEPENDS}
do
	echo "sudo luarocks install ${k}"
	sudo luarocks install  ${k}
done
