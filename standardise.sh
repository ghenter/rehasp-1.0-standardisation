# Script to create two standrardised versions of the REHASP 1.0 database
./standardise_folder.sh local.conf.48k > 48k.log 2>&1
./standardise_folder.sh local.conf.16k > 16k.log 2>&1
