#!/bin/bash
#Usage "blacklist_maker.sh system scene"

scene="$(echo ${2} | awk -F'.' '{print $2}')"

echo -n "Detecting scene changes..."
for f in *.mp4; do
       ffmpeg -i "${f}" -filter:v "select='gt(scene,${2})',showinfo" -y -f null - 2> "${f%.mp4}.ff${scene}"
done
echo "Done."

echo -n "Cleaning up output..."
for f in *.ff${scene}; do
        grep showinfo "${f}" | grep pts_time:[0-9.]* -o | cut -c10- | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}' | awk '$0>5' | awk '!seen[$0]++' > "${f%.ff${scene}}.stamp"
done
echo "Done."

if [ "${3}" != "nofilter" ]; then
	echo -n "Filtering consecutive frames out..."
	for f in *.stamp; do
		cat "${f}" | while read line; do
		if [ ! -z "${prev}" ]; then
			line1="${prev}"	
			line2="${line}"
				if [ "$((${line2} - ${line1}))" -gt "1" ]; then
					echo "${line2}" >> st.tmp
				fi
		fi
			   prev="${line}"
		done
		if [ -f st.tmp ]; then
			mv st.tmp "${f}"
		else
			echo ""> "${f}"
		fi
		
	done
	echo "Done."
fi


if [ -f "${1}_bl.tmp" ]; then
        rm ${1}_bl.tmp
fi

for f in *.stamp; do
        if [[ "$(cat "${f}" | wc -l)" -lt "2" ]]; then
                echo "${f}" >> ${1}_bl.tmp
        fi
done

cat ${1}_bl.tmp |  cut -d "(" -f1-3 | awk -F '.st${scene}' '{print $1}' | cut -d "[" -f1 | awk '!seen[$0]++' > ${1}_bl.txt

echo "${1}_bl.txt was created"
