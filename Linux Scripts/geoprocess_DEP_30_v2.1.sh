#!/usr/bin/env bash
#######################################################################################################
# Purpose: This script 1. takes a text file containing a list of HUC6 format watershed numbers as input
#                      2. sets up SLURM submission settings
#                      3. sets up input file directories and required buffer size
#                      4. parse input and execute "Geoprocess_single_watershed_DEP_30_v2.1.sh" script 
#                         per HUC6 format watershed number
#
# USAGE_Direct: ./geoprocess_DEP_30_v2.1.sh [HUC6 format watershed numbers text file]
# USAGE_SLURM: sbatch geoprocess_DEP_30_v2.1.sh [HUC6 format watershed numbers text file]
#
# Author: PoChou Su                          cskenny@nmsu.edu
# Author: Colby Brungard                     cbrung@nmsu.edu
# Last Modified: Feb 18 2019
# Version: 2.1
#######################################################################################################

######## SLURM submission settings ###########
#SBATCH -p shas
#SBATCH --qos=long
#SBATCH --time=7-00:00:00
#SBATCH -c 24  
#SBATCH -N 1
#SBATCH --mail-user=cskenny@nmsu.edu
#SBATCH --mail-type=FAIL,END

USAGE="Direct Execute: $BASH_SOURCE [HUC6 format watershed numbers text file]\nSubmit to SLURM: sbatch $BASH_SOURCE [HUC6 format watershed numbers text file]"

######## Input file directories ##########
export INPUT_DIR=/home/cskenny@xsede.org/project/Geoprocess

#name of DEM to calculate derivatives from
export DEM=${INPUT_DIR}/DEP_30/DEMmosaic_30_CONUS.tif
  #check if DEM file is missing
  if ! [[ -s $DEM ]]; then
       echo "DEM file $DEM does not exist or is empty"
       exit 1
  fi

#path to HUC6 watershed files. Both are needed because I clip by the unprojected shapefile and then trim with the projected shapefile.
export indexA=${INPUT_DIR}/HUC6_Map/wbdhu6_a_us_september2017_CONUS_4269_validGeom.shp
  #check if indexA is missing
  if ! [[ -s $indexA ]]; then
       echo "IndexA file $indexA does not exist or is empty"
       exit 1
  fi

export indexB=${INPUT_DIR}/HUC6_Map/wbdhu6_a_us_september2017_CONUS_Albers_validGeom.shp
  #check if indexB is missing
  if ! [[ -s $indexB ]]; then
       echo "IndexB file $indexB does not exist or is empty"
       exit 1
  fi

#Set a primary and secondary buffer distance in number of pixels. The primary will be used when clipping the DEM by HUC6 watersheds. The secondary will be used to trim off edge effects of each derivative, but leave enough to feather the edges when mosaicking.
export bufferA=34
export bufferB=10

######## Parse input and execute Geoprocess_single_watershed_DEP_30_v2.1.sh #########
#check if HUC6 text file is missing
if ! [[ -s $1 ]]; then
       echo "Input file $1 does not exist or is empty"
       echo -e $USAGE
       exit 1
   #check if Geoprocess_single_watershed_DEP_30_v2.1.sh is missing
   elif ! [[ -s Geoprocess_single_watershed_DEP_30_v2.1.sh ]]; then 
       echo "Geoprocess_single_watershed_DEP_30_v2.1.sh does not exist or is empty"
       echo -e $USAGE
       exit 1
   else 
   for i in $(<$1); do
      #Usage:Geoprocess_single_watershed_DEP_30_v2.1.sh -n [number of core] [HUC6 tile number]
                                                   #Use all cores by default
      source Geoprocess_single_watershed_DEP_30_v2.1.sh -n $(nproc) $i
   done
fi
