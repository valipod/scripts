for file in *.mkv
do
  if [ -z "$1" ];
    then
	  #read -t 5 -p "No arguments supplied (proceed in 5 seconds or ENTER) ..."
      ffmpeg -i "$file" -i "${file%.mkv}.ro.srt" -map 0:v:0 -map 0:a:0 -map 1:0 -map 0:s:0 -metadata:s:s:0 language=ron -c copy -metadata:s:a:0 title= -metadata title= -metadata:s:v title= -metadata:s:s:1 title= -disposition:s:0 default -disposition:s:1 original -max_interleave_delta 0 "../${file}"
  elif [ -z "$2" ];
    then
    #read -t 5 -p "Target will be saved in $1 (proceed in 5 seconds or ENTER) ..."
    ffmpeg -i "$file" -i "${file%.mkv}.ro.srt" -map 0:v:0 -map 0:a:0 -map 1:0 -map 0:s:0 -metadata:s:s:0 language=ron -c copy -metadata:s:a:0 title= -metadata title= -metadata:s:v title= -metadata:s:s:1 title= -disposition:s:0 default -disposition:s:1 original -max_interleave_delta 0 "$1/${file}"
  else
    #read -t 5 -p "Target will be saved in $1/$2 (proceed in 5 seconds or ENTER) ..."
    ffmpeg -i "$file" -i "${file%.mkv}.ro.srt" -map 0:v:0 -map 0:a:0 -map 1:0 -map 0:s:0 -metadata:s:s:0 language=ron -c copy -metadata:s:a:0 title= -metadata:s:v title= -metadata title= -metadata:s:s:1 title= -disposition:s:0 default -disposition:s:1 original -max_interleave_delta 0 "$1/$2"
  fi
done
