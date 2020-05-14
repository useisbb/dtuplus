LUA_VER=`dpkg -s lua5.1 | grep 'installed'`
if [ -z "$LUA_VER" ];
then
        echo "You need install lua5.1,run sudo apt install lua5.1"
        exit 0
fi

DEPENDS="chronos elscheduler lpack lsocket lua-fs-module lua-json luabitop luars232"
for k in ${DEPENDS}
do
	echo "sudo luarocks install ${k}"
	sudo luarocks install  ${k}
done
