#!/bin/bash
#Usage "blacklist_maker.sh system"
#Usage options "noscene nostamp filter brackets"

args="$(echo "$@")"
scene="1"
if [[ "$1" == "arcade" ]]; then
	scene="005"
fi

cd /mnt/c/SAM/${1}

if [[ -z "${1}" ]]; then
	echo "Specify system. Aborting.."
	exit
fi

if [[ "${args}" != *"noscene"* ]]; then
	echo -n "Detecting scene changes..."
	for f in *.mp4; do
		if [[ ! -e "${f%.mp4}.ff${scene}" ]]; then
		   ffmpeg -i "${f}" -filter:v "select='gt(scene,0.${scene})',showinfo" -y -f null - 2> "${f%.mp4}.ff${scene}"
		fi
	done
	echo "Done."

fi

if [[ "${args}" != *"nostamp"* ]]; then
	echo -n "Creating .st${scene} files..."
	for f in *.ff${scene}; do
		if [[ ! -e "${f%.ff${scene}}.st${scene}" ]]; then
			grep showinfo "${f}" | grep pts_time:[0-9.]* -o | cut -c10- | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}' | awk '$0>5' | awk '!seen[$0]++' > "${f%.ff${scene}}.st${scene}"
		fi
	done
	echo "Done."
fi

if [ -f "${1}_gamelist_hdmi.txt" ]; then
	echo -n "Creating fake .st${scene} files..."
	ls *.mp4 | awk -F"/" '{print $(NF)}' | awk -F"." '{OFS=FS; NF=NF-1; print $0}' > "${1}_gamelist_mp4.txt"
	#add a . for unique files
	sed -i 's/$/./' "${1}_gamelist_mp4.txt"
	#filter out all mp4s already created
	fgrep -vf "${1}_gamelist_mp4.txt" "${1}_gamelist_hdmi.txt" > "${1}_gamelist_missingmp4.txt"
	# prepare for filtering out other roms with longer names
	sed -i 's/.$//' "${1}_gamelist_mp4.txt"
	fgrep -f "${1}_gamelist_mp4.txt" "${1}_gamelist_missingmp4.txt" | awk -F"/" '{print $(NF)}' | awk -F"." '{OFS=FS; NF=NF-1; print $0}' | sort -u > "${1}_gamelist_fakemp4.txt"
	while IFS= read -r line; do
		#touch "$line.st1"
		touch "$line.st${scene}"
	done < "${1}_gamelist_fakemp4.txt"
	echo "Created $(wc -l <"${1}_gamelist_fakemp4.txt") fake .st1 files."
fi

if [[ "${args}" == *"filter"* ]]; then
	echo -n "Filtering consecutive frames out..."
	for f in *.st${scene}; do
		cat "${f}" | while read line; do
		if [ ! -z "${prev}" ]; then
			line1="${prev}"	
			line2="${line}"
				if [ "$((${line2} - ${line1}))" -gt "1" ]; then
					echo "${line1}" >> st.tmp
					echo "${line2}" >> st.tmp
				fi
		fi
			   prev="${line}"
		done
		
		if [ -f st.tmp ]; then
			mv st.tmp "${f%.st${scene}}.st${scene}"
		elif [[ $(cat "${f}" | wc -l) -gt "3" ]]; then
			cat "${f}" > "${f%.st${scene}}.st${scene}"
		else
			echo ""> "${f%.st${scene}}.st${scene}"
		fi
		
	done
	echo "Done."
fi


if [ -f "${1}_bl.tmp" ]; then
        rm ${1}_bl.tmp
fi

echo -n "Creating final list..."

for f in *.st${scene}; do
	if [[ "$(cat "${f}" | wc -l)" -lt "2" ]]; then
			echo "${f}" >> ${1}_bl.tmp
	fi
done


if [[ "${args}" != *"brackets"* ]]; then
	cat ${1}_bl.tmp | awk -F.st"${scene}" '{print $1}'| awk '!seen[$0]++' > ${1}_bl.txt
else
	cat ${1}_bl.tmp | cut -d "(" -f1-3 | awk -F.st"${scene}" '{print $1}' | cut -d "[" -f1 | awk '!seen[$0]++' > ${1}_bl.txt
fi

if [[ "${args}" == *"nobrackets"* ]]; then
	cat ${1}_bl.tmp | cut -d "(" -f1 | awk -F.st"${scene}" '{print $1}'| awk '!seen[$0]++' > ${1}_bl.txt
fi
echo "Done."

if [ -e /mnt/c/SAM/${1}_blacklist.txt ]; then
	sort /mnt/c/SAM/${1}/${1}_bl.txt /mnt/c/SAM/${1}_blacklist.txt | awk '!seen[$0]++' > /mnt/c/SAM/tmp && cp --force /mnt/c/SAM/tmp /mnt/c/SAM/${1}_blacklist.txt
	echo "${1}_blacklist.txt merge successful"
else
	cp /mnt/c/SAM/${1}/${1}_bl.txt /mnt/c/SAM/${1}_blacklist.txt
	echo "${1}_blacklist.txt was created."
fi
