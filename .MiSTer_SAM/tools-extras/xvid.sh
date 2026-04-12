#!/bin/bash
input_dir="/Users/christoph/video/640x480"
output_dir="/Users/christoph/video/640x480xvid"
resolution="640x480"  # Set the desired resolution here
video_bitrate="2000k"
audio_bitrate="128k"

# Create the output directory if it doesn't exist
mkdir -p "$output_dir"

for file in "$input_dir"/*.mov; do
  filename=$(basename "$file")
  output_file="$output_dir/${filename%.*}.avi"

#ffmpeg -y -i "$file" -vf "scale=640:240,setsar=1:1" -c:v mpeg2video -b:v 5000k -c:a ac3 -b:a 128k "$output_file"
ffmpeg -y -i "$file" -c:v mpeg4 -vtag xvid -b:v 4000k "$output_file"

done


