rehasp-1.0-standardisation
==========================

This git repository contains bash scripts used to transform unprocessed 96 kHz 
recordings from the **REHASP 1.0 corpus** into standardised wav files at 16 
and 48 kHz sampling rate.

The canonical, standardised wav files distributed as part of the REHASP 1.0 
corpus were created using this code.

### Requirements:
* **SoX: Sound eXchange**
  - Available at http://sox.sourceforge.net/
  - Only the `sox` command is used
  - SoX v14.4.1 was used to generate the files in the REHASP 1.0 corpus release
* **ITU-T G.191 Software tools for speech and audio coding standardization**
  - Available at http://www.itu.int/rec/T-REC-G.191/en
  - Only the `sv56demo` command is used
  - ITU-T Recommendation G.191 (03/10) code was used to generate the files in 
    the REHASP 1.0 corpus release
* **The REHASP 1.0 corpus 96 kHz recordings**
  - Not yet available online as of 2014-12-01;
    contact the code author with any inquiries

### Output:
* `16k_std/`
* `48k_std/`
  - Folders with standardised wav files at given sampling rates
  - Output folder locations are configurable
  - The internal folder structure mirrors the selected data source folder

### Steps to use:
1. Download and extract the REHASP 1.0 96 kHz unprocessed recordings 
   (available in the full version of the corpus)
2. Download and install or compile the software listed in the *Requirements* 
   section
3. Clone the standardisation repository to a suitable folder, e.g., using 
   `git clone https://github.com/ghenter/rehasp-1.0-standardisation.git` 
4. Change directory to the `rehasp-1.0-standardisation` folder
5. Edit the configuration files `local.conf.*` to match your local setup:
  - Edit `$SOX_PATH` and `$ITU_PATH` to point to the executable binaries of 
    the relevant tools
  - Select relevant `$SED_OPT` for GNU or BSD sed
  - Edit `$DATA_DIR` to point to the `96k/` REHASP 1.0 source data folder
  - Edit `$OUT_DIR` to point to the desired output folder
  - Edit `$TMP_DIR` to point to the desired folder where temporary files 
    will be stored (these must be removed manually to clean up)
  - Edit any other processing options as desired
6. Ensure that the script files are executable by issuing `chown u+x *.sh`
7. Issue the command `./standardise.sh` to run the standardisation script

### Notes:
* The code was tested on Mac OS X version 10.9
* Processing can take two to three hours on a decently fast machine
* Be sure to look at the log files (e.g., `more 48k.log`) to verify that no 
  errors occurred during processing
* Allow at least 65 GiB of disk space for source, output, and temporary data