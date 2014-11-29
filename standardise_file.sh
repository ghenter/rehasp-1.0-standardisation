#!/bin/bash
#$ -S /bin/bash
# Script to standardise a wav file using SoX and ITU-T P.56

# Check number of arguments
if (( "$#" < "2" )); then
   echo "Usage:"
   echo "$0 config_file input_wav"
   exit 1
fi

# Load configuration file
CONFIG_FILE=$1
. ${CONFIG_FILE}
if (( $?>0 ));then echo "Error; exiting."; exit 1; fi
inwav=$2
outwav=$3

# Set command path
export PATH=${SOX_PATH}:${PATH}
export PATH=${ITU_PATH}:${PATH}

# Tokenise file names
chmod -x $inwav
inbase=`basename $inwav .wav`
indir=`dirname $inwav`

outbase=`echo ${inbase} | s/${inDataId}/${outDataId}/`
outdir=`echo ${indir} | s/${DATA_DIR}/${OUT_DIR}/`

# Create directories if necessary
mkdir -p ${TMP_DIR}/raw
mkdir -p ${TMP_DIR}/norm

mkdir -p ${outdir}

# Create temporary (processed but unnormalised) raw file
sox ${soxdebug} ${inwav} \
    -e signed-integer -b 16 \
    ${TMP_DIR}/raw/${inbase}.raw \
    remix ${channelnum} \
    sinc ${hpflags} -t ${hptbw} ${hpfreq} \
    rate ${rateflags} ${outrate}

# Use sv56demo to normalise raw file
sv56demo -q -log ${TMP_DIR}/norm/${inbase}.log -lev $level -sf ${outrate} \
    ${TMP_DIR}/raw/${inbase}.raw ${TMP_DIR}/norm/${inbase}.raw 640 \
    2> /dev/null # Output stderr to /dev/null to avoid noise in log file

# Check if the amplitude normalisation created a clipped waveform
if test -s ${TMP_DIR}/norm/${inbase}.log
then
    if [ `grep -c "the dB level chosen causes SATURATION"  ${TMP_DIR}/norm/${inbase}.log` -eq 1 ];
    then
        echo "...${inbase}.wav was skipped due to SATURATION..."
        rm -f ${TMP_DIR}/raw/${inbase}.raw
        exit 0
    fi
fi

# Extract normalisation factor from sv56demo log file
normcoeff=1 # Add functionality here

echo sox ${soxdebug} ${inwav} \
    ${outbase}/${outbase}.wav \
    remix ${channelnum} \
    vol ${normcoeff} \
    sinc ${hpflags} -t ${hptbw} ${hpfreq} \
    rate ${rateflags} ${outrate}

exit 0 # Exit prematurely since implementation is currently incomplete

# Create properly normalised, processed file
sox ${soxdebug} ${inwav} \
    ${outbase}/${outbase}.wav \
    remix ${channelnum} \
    vol ${normcoeff} \
    sinc ${hpflags} -t ${hptbw} ${hpfreq} \
    rate ${rateflags} ${outrate}


# Determine sampling rate 
inputrate=`ch_wave -info $inwav | grep "Sample rate" | awk '{print $3}'`

# Precision conversion to 16 bits with normalisation if necessary and pick out a single channel
wav2raw +s -N -${channel} -d ${TMP_DIR}/raw/ $inwav

# Apply high pass filter (70 Hz), choose the first channel only and conduct zero checking 
ch_wave -itype raw -f $inputrate -scale 0.95 -otype raw ${TMP_DIR}/raw/${inbase}.raw \
    | ch_wave -itype raw -f $inputrate -hpfilter 70 -forder 6001 -F $inputrate -otype raw \
    | x2x -o +sa\
    | awk 'BEGIN{long=0;value=0}((value==$1)&&(long>10)){long++}((value==$1)&&(long<=10)){print $1;long++}(value!=$1){long=0; value=$1 ; print $1}'\
    | x2x -o +as \
    > ${TMP_DIR}/raw/${inbase}.raw_orig

# Check the speech active level. If audio includes speech, conduct amplitude normalisation
# If not, this does not output anything since they have silence or idle noise only

# Check if the amplitude normalisation created clipped waveform
if test -s ${TMP_DIR}/vad/${inbase}.log  
then
    if [ `grep -c "the dB level chosen causes SATURATION"  ${TMP_DIR}/vad/${inbase}.log` -eq 1 ]; 
    then
        echo "...${inbase}.wav was skipped due to SATURATION..."
        rm -f ${TMP_DIR}/raw/${inbase}.raw_norm 
        exit 0
    fi
else
    echo "VAD failed for ${inbase}.wav. Please check this audio file"
    exit 1 
fi

if test -s ${TMP_DIR}/raw/${inbase}.raw_norm
then
    # Get activity factor
    activity=`grep "Activity factor" ${TMP_DIR}/vad/${inbase}.log | awk '{print $(NF-1)"/100"}' | bc -l | awk '{printf "%.2f\n", $1}'`
    # Compute log-energy profile (dB)
    shiftpoint=`echo "$rate * $shift / 1000" | bc -l | awk '{printf "%d\n", $1}'` # e.g. Frame shift in point (80 = 16000 * 0.005)
    windowpoint=`echo "$rate * $windur / 1000" | bc -l | awk '{printf "%d\n", $1}'` # e.g. Window length in point (400 = 16000 * 0.025)
    x2x -o +sf ${TMP_DIR}/raw/${inbase}.raw_norm \
        | frame -l $windowpoint -p $shiftpoint \
        | acorr -m 0 -l $windowpoint \
        | sopr -f 0.1 -LOG10 -m 10 \
        > ${TMP_DIR}/vad/${inbase}.nrg
    # Average level (dB)
    meanlev=`average ${TMP_DIR}/vad/${inbase}.nrg | x2x -o +fa`
    # Voice activity threshold
    vad_thres=`echo "scale=5;$meanlev - 10*l($activity)/l(10)" | bc -l | awk '{printf "%.2f\n", $1}'`
    # Voice activity detection
    x2x -o +fa ${TMP_DIR}/vad/${inbase}.nrg \
        | awk 'BEGIN{thres='$vad_thres';shift='$shift'}{if ($1 > thres) print NR*shift/1000}' \
        > ${TMP_DIR}/vad/${inbase}.vad
    
    speechstarttime=`head -1 ${TMP_DIR}/vad/${inbase}.vad`
    speechendtime=`tail -1 ${TMP_DIR}/vad/${inbase}.vad`
    
    fileend=`ch_wave -info -f $rate -itype raw ${TMP_DIR}/raw/${inbase}.raw_norm | grep "Duration" | awk '{print $NF}'`
    silenceend=`echo "$fileend - $speechendtime" | bc -l | awk '{printf "%.2f\n", $1}'`
    
    # Judge if silence in the beginnning of audio file is too long or not 
    isSSilenceLong=`echo "$speechstarttime > $maxstartsil" | bc -l | awk '{printf "%d\n", $1}'`
    if [ $isSSilenceLong -eq 1 ] 
    then 
        trimstart=`echo "$speechstarttime - $maxstartsil" | bc -l | awk '{printf "%.2f\n", $1}'` 
    else
        trimstart='0'
    fi 
    
    # Judge if silence in the end of audio file is too long or not  
    isESilenceLong=`echo "$silenceend > $maxendsil" | bc -l | awk '{printf "%d\n", $1}'`
    if [ $isESilenceLong -eq 1 ]         
    then 
        trimend=`echo "$speechendtime + $maxendsil" | bc -l | awk '{printf "%.2f\n", $1}'` 
    else
        trimend=`echo "$fileend" | bc -l | awk '{printf "%.2f\n", $1}'`
    fi 
    
    # Discard audio files that have too short silence 
    isSSilenceShort=`echo "$speechstarttime < $minstartsil" | bc -l | awk '{printf "%d\n", $1}'`
    isESilenceShort=`echo "$silenceend < $minendsil" | bc -l | awk '{printf "%d\n", $1}'`
    
    if [ $isSSilenceShort -eq 0 -a $isESilenceShort -eq 0 ]
    then 
        # Trim silences
        sox $inwav $outwav trim =$trimstart =$trimend
        
        # Log trimming data
        trimmedlen=`echo "$trimend - $trimstart" | bc -l | awk '{printf "%.2f\n", $1}'`
        echo ${inbase}':'$speechstarttime':'$trimmedlen':'$silenceend >> ${TMP_DIR}/trimlengths.log
    else 
        echo ${inbase}':'$speechstarttime':'0':'$silenceend >> ${TMP_DIR}/trimlengths.log
        echo "...${inbase}.wav was discarded due to short silence lengths..."
        exit 0
    fi
    
    # Touch the trimmed file to restore its recording-time timestamps
    touch -r $inwav $outwav
fi

 
