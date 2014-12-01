#!/bin/bash
#$ -S /bin/bash
# Script to recursively standardise all wav files in a directory

# Check number of arguments
if (( "$#" < "1" )); then
   echo "Usage:"
   echo "$0 config_file"
   exit 1
fi

# Load configuruation file
echo "Loading configuration file..."
CONFIG_FILE=$1
. ${CONFIG_FILE}
if (( $?>0 ));then echo "Error; exiting."; exit 1; fi

# Create directories
echo "Creating directories..."

rm -rf ${TMP_DIR}
mkdir -p ${TMP_DIR}/raw
mkdir -p ${TMP_DIR}/norm

rm -rf ${OUT_DIR}
mkdir -p ${OUT_DIR}

# Standardise all wav files in the data directory
echo "Standardising recording data..."

for wavfile in `find ${DATA_DIR} -type f -name '*.wav'`; do
    #echo ${wavfile} # Uncomment to print the name of each file being processed
    ${STD_COMMAND} ${CONFIG_FILE} ${wavfile}
done

echo "Done"

exit 0
