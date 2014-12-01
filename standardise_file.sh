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

outbase=`echo ${inbase} | sed s/${inDataId}/${outDataId}/`
outdir=`echo ${indir} | sed s#${DATA_DIR}#${OUT_DIR}#` # Assumes no '#' in path

# Store log file paths in single variables for convenience
soxlog=${TMP_DIR}/raw/${inbase}.sox.log
sv56log=${TMP_DIR}/norm/${inbase}.sv56.log

# Create directories if necessary
mkdir -p ${TMP_DIR}/raw
mkdir -p ${TMP_DIR}/norm

mkdir -p ${outdir}

# Most of the work from now on is to compute the proper normalisation factor

safegain=1 # "Safety-margin" pre-gain factor
makeraw=1 # Loop variable

while [ ${makeraw} -eq 1 ]
do
    # Create temporary (processed but unnormalised) raw file
    sox ${soxdebug} ${inwav} \
        -e signed-integer -b ${outbits} ${TMP_DIR}/raw/${inbase}.raw \
        remix ${channelnum} \
        vol ${safegain} \
        sinc ${hpflags} -t ${hptbw} ${hpfreq} \
        rate ${rateflags} ${outrate} \
        2> ${soxlog}
    
    # Check if clipping occurred during SoX operations
    if test -e ${soxlog}
    then
        if [ `grep -c "clip" ${soxlog}` -gt 0 ];
        then
            # Reduce the gain on the input file and retry
            safegain=`echo 0.75\*${safegain} | bc -l`
            echo "...reducing pre-gain on ${inbase}.wav"\
                "to ${safegain} due to clipping..."
        else
            makeraw=0 # No need to retry; exit loop
        fi
    else
        echo "...${inbase}.wav was skipped due to failure to find sox log file..."
        rm -f ${TMP_DIR}/raw/${inbase}.raw
        exit 0
    fi
done

# Use sv56demo to normalise raw file
sv56demo -q -log ${sv56log} \
    -lev ${outlevel} -sf ${outrate} \
    ${TMP_DIR}/raw/${inbase}.raw \
    ${TMP_DIR}/norm/${inbase}.raw 640 \
    2> /dev/null # Output stderr to /dev/null to avoid noise in log file

# Check if the amplitude normalisation created a clipped waveform
if test -s ${sv56log}
then
    if [ `grep -c "the dB level chosen causes SATURATION" ${sv56log}` -eq 1 ]
    then
        echo "...${inbase}.wav was skipped due to saturation..."
        rm -f ${TMP_DIR}/raw/${inbase}.raw
        rm -f ${TMP_DIR}/norm/${inbase}.raw
        exit 0
    fi
else
    echo "...${inbase}.wav was skipped due to failure to find sv56 log file..."
    rm -f ${TMP_DIR}/raw/${inbase}.raw
    rm -f ${TMP_DIR}/norm/${inbase}.raw
    exit 0
fi

# Extract the normalisation factor from the sv56demo log file
normcoeff=`grep 'Norm factor desired' ${sv56log} \
    | grep -o '[^ ]*[ ]*\[times\][ ]*$' \
    | sed ${SED_OPT} 's/[ ]*\[times\][ ]*$//g'`

# Include the effect of the safety-margin pre-gain factor
normcoeff=`echo ${safegain}\*${normcoeff} | bc -l`

# Create properly normalised, processed final file
sox ${soxdebug} ${inwav} \
    -b ${outbits} ${outdir}/${outbase}.wav \
    remix ${channelnum} \
    vol ${normcoeff} \
    sinc ${hpflags} -t ${hptbw} ${hpfreq} \
    rate ${rateflags} ${outrate}

# Append the normalisation factor to a log file
echo ${inbase}':'${normcoeff} >> ${TMP_DIR}/normcoeffs.log

exit 0
