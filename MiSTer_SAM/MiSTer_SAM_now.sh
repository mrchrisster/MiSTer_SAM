#!/bin/bash

#======== INI VARIABLES ========
# Change these in the INI file

#======== GLOBAL VARIABLES =========
declare -g mrsampath="/media/fat/Scripts/.MiSTer_SAM"
declare -g misterpath="/media/fat"

#======== DEBUG VARIABLES ========
samquiet="Yes"

#======== OPTIONS ========
	for arg in "${@}"; do
		case ${arg,,} in
			spy)
				PID=$(ps aux |grep MiSTer_SAM.sh |grep -v grep |awk '{print $1}')
				echo "Attaching MiSTer SAM to current shell"
				THIS=$0
				ARGS=$@
				name=$(basename $THIS)
				quiet="no"
				nopt=""
				shift $((OPTIND-1))
				fds=""
				if [ -n "$nopt" ]; then
					for n_f in $nopt; do
						n=${n_f%%:*}
						f=${n_f##*:}
						fds="$fds $n"
						fns[$n]=$f
					done
				fi
				if [ -z "$stdout" ] && [ -z "$stderr" ] && [ -z "$stdin" ] && [ -z "$nopt" ]; then
					[ -e /proc/$$/fd/0 ] &&  stdin=$(readlink /proc/$$/fd/0)
					[ -e /proc/$$/fd/1 ] && stdout=$(readlink /proc/$$/fd/1)
					[ -e /proc/$$/fd/2 ] && stderr=$(readlink /proc/$$/fd/2)
				fi
				gdb_cmds () {
					local _name=$1
					local _mode=$2
					local _desc=$3
					local _msgs=$4
					local _len
					[ -w "/proc/$PID/fd/$_desc" ] || _msgs=""
					[ -z "$_name" ] && return
				}
				trap '/bin/rm -f $GDBCMD' EXIT
				GDBCMD=$(mktemp /tmp/gdbcmd.XXXX)
				{
					#Linux file flags (from /usr/include/bits/fcntl.sh)
					O_RDONLY=00
					O_WRONLY=01
					O_RDWR=02
					O_CREAT=0100
					O_APPEND=02000
					gdb_cmds "$stdin"  $((O_RDONLY)) 0 "$msg_stdin"
					gdb_cmds "$stdout" $((O_WRONLY|O_CREAT|O_APPEND)) 1 "$msg_stdout"
					gdb_cmds "$stderr" $((O_WRONLY|O_CREAT|O_APPEND)) 2 "$msg_stderr"
					for n in $fds; do
						msg="Descriptor $n of $PID is remapped to ${fns[$n]}\n"
						gdb_cmds ${fns[$n]} $((O_RDWR|O_CREAT|O_APPEND)) $n "$msg"
					done
				} > $GDBCMD

				if gdb -batch -n -x $GDBCMD >/dev/null </dev/null; then
					[ "$quiet" != "yes" ] && echo "Success" >&2
				else
					warn "Remapping failed"
				fi
				#cp $GDBCMD /tmp/gdbcmd
				rm -f $GDBCMD
				exit 0
				;;
		esac
	done

#========= PARSE INI =========
# Read INI
if [ -f "${misterpath}/Scripts/MiSTer_SAM.ini" ]; then
	. "${misterpath}/Scripts/MiSTer_SAM.ini"
	IFS=$'\n'
fi

# Remove trailing slash from paths
for var in mrsampath misterpath mrapathvert mrapathhoriz arcadepath gbapath genesispath megacdpath neogeopath nespath snespath tgfx16path tgfx16cdpath; do
	declare -g ${var}="${!var%/}"
done


#======== DEBUG OUTPUT =========
if [ "${samquiet,,}" == "no" ]; then
	echo "********************************************************************************"
	#======== GLOBAL VARIABLES =========
	echo "mrsampath: ${mrsampath}"
	echo "misterpath: ${misterpath}"
	#======== LOCAL VARIABLES ========
	echo "********************************************************************************"
fi

#======== NUCLEAR LAUNCH DETECTED ========
"${mrsampath}/MiSTer_SAM.sh" ${@} &
exit 0
