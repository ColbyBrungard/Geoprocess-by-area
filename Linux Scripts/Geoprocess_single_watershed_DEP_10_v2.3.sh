#!/usr/bin/env bash
###############################################################################################################
# Purpose: Calculate multiple terrain derivatives for a HUC8 format watershed
#
# USAGE: ./Geoprocess_single_watershed_DEP_10_v2.3.sh -n [number of core] [HUC8 tile number]
#
# Author: PoChou Su                          cskenny@nmsu.edu
#         Colby W. Brungard PhD               cbrung@nmsu.edu

# Last Modified: Feb 19 2019
# Version: 2.3
################################################################################################################

USAGE="USAGE: $BASH_SOURCE -n [number of core] [HUC8 tile number]"

#modify the following paths to match your saga install and datafiles.
module load saga-6.4.0

#Parse input variables. These input variables are FIXED, change here if you want to change how this script takes input variable
#Check number of input variables
if [[ $# != 3 ]]; then
   echo "Incorrect number of input variables! There sholud be 3 input variables, you input $#!"
   echo $USAGE
   exit 1
fi
# $1:-n
if [[ $1 != -n ]]; then
   echo "Missing '-n'"
   echo $USAGE
   exit 1
fi
# $2:[number of core] 
if ! [[ $2 =~ [[:digit:]]+ ]]; then          #check if input integer
   echo "Number of core is not integer!!"
   echo $USAGE
   exit 1
fi
   #check if execute directly or submit to SLURM
if [[ -z $SLURM_JOB_CPUS_PER_NODE ]]; then
   if (( $2 > 0 && $2 <= $(nproc --all) )) ; then
      echo "Execute directly"
      NumOfCore=$2
   else
      echo "Execute directly"
      echo "Number of core is not between 1 and $(nproc --all)"
      echo "Default to use $(nproc --all) cores"
      NumOfCore=$(nproc --all)
   fi
elif (( $2 > 0 && $2 <= $SLURM_JOB_CPUS_PER_NODE )); then
      echo "Submitted to SLURM"
      NumOfCore=$2
   else
      echo "Submitted to SLURM"
      echo "Number of core is not between 1 and $SLURM_JOB_CPUS_PER_NODE"
      echo "Default to use $SLURM_JOB_CPUS_PER_NODE cores"
      NumOfCore=$SLURM_JOB_CPUS_PER_NODE
fi
SAGA_parallel="saga_cmd -c=$NumOfCore"

#The column name of the shapefiles attribute table with the HUC8 values. 
fieldname="HUC8"

# $3:[HUC8 tile number]
#tile are the names/values of each polygon. This script handle one tile only. 
tile=$3

#start time 
startTime=$(date +%F\ %H:%M:%S)

##############  1. Preprocessing  ##############
#Create subdirectories to hold derivatives
working_dir=/scratch/summit/cskenny@xsede.org/Result/HUC8/
mkdir -p $working_dir/$tile

#Compress image file function
function Compress()  # $1: "_" + "name of derivative"
{
  echo "Compressing $(ls -lh $working_dir/$tile/${tile}${1}.tif) ..."
  xz -T $NumOfCore -9 -k $working_dir/$tile/${tile}${1}.tif 
  echo "Testing $(ls -lh $working_dir/$tile/${tile}${1}.tif.xz) ..."
  xz -T $NumOfCore -t $working_dir/$tile/${tile}${1}.tif.xz 
  echo "Deleting $working_dir/$tile/${tile}${1}.tif ..."
  rm $working_dir/$tile/${tile}${1}.tif 
}

#Clip DEM to HUC8 watershed boundary.
echo now subsetting $fieldname $tile
gdalwarp --config GDAL_CACHEMAX 500 -wm 500 -multi -wo NUM_THREADS=$NumOfCore -t_srs "+proj=aea +lat_1=29.5 +lat_2=45.5 +lat_0=23 +lon_0=-96 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs +ellps=GRS80 +towgs84=0,0,0" -tr 10 10 -r bilinear -cutline $indexA -cwhere "$fieldname = '${tile}'" -crop_to_cutline -cblend $bufferA $DEM $working_dir/$tile/${tile}.tif

#Smooth DEM to remove data artifacts using circle with radius of 4 cells) smoothing filter
echo now smoothing $fieldname $tile
$SAGA_parallel grid_filter 0 -INPUT=$working_dir/$tile/${tile}.tif -RESULT=$working_dir/$tile/${tile}_s.sgrd -METHOD=0 -KERNEL_TYPE=1 -KERNEL_RADIUS=2

Compress

#############  2. Calculate Derivatives  #############
#each code chunk follows the same format:
# 1. Calculate one derivative
# 2. Trim off the edges of each derivative by a fraction of the original buffer to remove cells effected by edge artifacts
  function Trim_gdalwarp() # $1: name of derivative
  {
    #Modified to change output file type and enforce default resolution.
    gdalwarp --config GDAL_CACHEMAX 500 -wm 500 -multi -wo NUM_THREADS=$NumOfCore -cutline $indexB -cwhere "$fieldname = '${tile}'" -cblend $bufferB -crop_to_cutline -tr 10 10 -r bilinear $working_dir/$tile/${tile}_${1}A.sdat $working_dir/$tile/${tile}_${1}.tif
  }

# 3. Remove intermediate files to save space.
  function Delete_Temp_Files()  # $1: name of derivative
  {
    echo "Deleting $working_dir/$tile/${tile}_${1}.mgrd $working_dir/$tile/${tile}_${1}.prj $working_dir/$tile/${tile}_${1}.sdat $working_dir/$tile/${tile}_${1}.sdat.aux.xml $working_dir/$tile/${tile}_${1}.sgrd"
    rm $working_dir/$tile/${tile}_${1}.mgrd $working_dir/$tile/${tile}_${1}.prj $working_dir/$tile/${tile}_${1}.sdat $working_dir/$tile/${tile}_${1}.sdat.aux.xml $working_dir/$tile/${tile}_${1}.sgrd
  }

#analytical hillshade ##########
echo now calculating analytical hillshade of $fieldname $tile
$SAGA_parallel ta_lighting 0 -ELEVATION=$working_dir/$tile/${tile}_s.sgrd -SHADE=$working_dir/$tile/${tile}_hsA.sgrd -METHOD=0 -UNIT=1
echo now trimming analytical hillshade of $fieldname $tile
Trim_gdalwarp hs
Delete_Temp_Files hsA
Compress _hs

#Profile, plan, longitudinal, cross-sectional, minimum, maximum, and total curvature ##########
echo now calculating Profile, plan, longitudinal, cross-sectional, minimum, maximum, and total curvature of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 0 -ELEVATION=$working_dir/$tile/${tile}_s.sgrd -C_PROF=$working_dir/$tile/${tile}_profcA.sgrd -C_PLAN=$working_dir/$tile/${tile}_plancA.sgrd -C_LONG=$working_dir/$tile/${tile}_lcA.sgrd -C_CROS=$working_dir/$tile/${tile}_ccA.sgrd -C_MINI=$working_dir/$tile/${tile}_mcA.sgrd  -C_MAXI=$working_dir/$tile/${tile}_mxcA.sgrd -C_TOTA=$working_dir/$tile/${tile}_tcA.sgrd -METHOD=6 -UNIT_SLOPE=2

echo now trimming Profile Curvature of $fieldname ${tile}
Trim_gdalwarp profc
Delete_Temp_Files profcA
Compress _profc

echo now trimming Plan Curvature of $fieldname ${tile}
Trim_gdalwarp planc
Delete_Temp_Files plancA
Compress _planc
   
echo now trimming Longitudinal Curvature of $fieldname ${tile}
Trim_gdalwarp lc
Delete_Temp_Files lcA
Compress _lc

echo now trimming Cross Sectional Curvature of $fieldname ${tile}
Trim_gdalwarp cc
Delete_Temp_Files ccA
Compress _cc

echo now trimming Minimum Curvature of $fieldname ${tile}
Trim_gdalwarp mc
Delete_Temp_Files mcA
Compress _mc

echo now trimming Maximum Curvature of $fieldname ${tile}
Trim_gdalwarp mxc
Delete_Temp_Files mxcA
Compress _mxc

echo now trimming Total Curvature of $fieldname ${tile}
Trim_gdalwarp tc
Delete_Temp_Files tcA
Compress _tc

#Slope and Aspect ##########			
echo now calculating Slope and Aspect of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 0 -ELEVATION=$working_dir/$tile/${tile}_s.sgrd -SLOPE=$working_dir/$tile/${tile}_slA.sgrd -ASPECT=$working_dir/$tile/${tile}_asA.sgrd -METHOD=1 -UNIT_SLOPE=1 -UNIT_ASPECT=1
echo now trimming Slope of $fieldname ${tile}
Trim_gdalwarp sl
Delete_Temp_Files slA
Compress _sl

echo now trimming Aspect of $fieldname ${tile}
Trim_gdalwarp as
Delete_Temp_Files asA
Compress _as


#Convergence Index ##########
echo now calculating Convergence Index of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 1 -ELEVATION=$working_dir/$tile/${tile}_s.sgrd -RESULT=$working_dir/$tile/${tile}_ciA.sgrd -METHOD=1 -NEIGHBOURS=1 
echo now trimming Convergence Index of $fieldname ${tile}
Trim_gdalwarp ci
Delete_Temp_Files ciA
Compress _ci


#Diurnal Anisotropic Heating ##########
echo now calculating Diurnal Anisotropic Heating of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 12 -DEM=$working_dir/$tile/${tile}_s.sgrd -DAH=$working_dir/$tile/${tile}_dahA.sgrd -ALPHA_MAX=225
echo now trimming Diurnal Anisotropic Heating of $fieldname ${tile}
Trim_gdalwarp dah
Delete_Temp_Files dahA
Compress _dah
	
	
#Terrain Ruggedness Index ##########
echo now calculating Terrain Ruggedness Index of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 16 -DEM=$working_dir/$tile/${tile}_s.sgrd -TRI=$working_dir/$tile/${tile}_triA.sgrd -MODE=1 -RADIUS=10
echo now trimming Terrain Ruggedness Index of $fieldname ${tile}
Trim_gdalwarp tri
Delete_Temp_Files triA
Compress _tri


#Terrain Surface Convexity ##########
echo now calculating Terrain Surface Convexity of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 21 -DEM=$working_dir/$tile/${tile}_s.sgrd -CONVEXITY=$working_dir/$tile/${tile}_tscA.sgrd -KERNEL=1 -TYPE=0 -EPSILON=0.0 -SCALE=10 -METHOD=1 -DW_WEIGHTING=3 -DW_BANDWIDTH=0.7
echo now trimming Terrain Surface Convexity of $fieldname ${tile}
Trim_gdalwarp tsc
Delete_Temp_Files tscA
Compress _tsc


#Positive Topographic Openness ##########
echo now calculating Positive Topographic Openness of $fieldname ${tile} 
$SAGA_parallel ta_lighting 5 -DEM=$working_dir/$tile/${tile}_s.sdat -POS=$working_dir/$tile/${tile}_poA.sgrd -RADIUS=$bufferA -METHOD=1 -DLEVEL=3.0 -NDIRS=8
echo now trimming Positive Topographic Openness of $fieldname ${tile}
Trim_gdalwarp po
Delete_Temp_Files poA
Compress _po


#Mass Balance Index #########
echo now calculating Mass Balance Index of $fieldname ${title}
$SAGA_parallel ta_morphometry 10 -DEM=$working_dir/$tile/${tile}_s.sdat -MBI=$working_dir/$tile/${tile}_mbiA.sgrd -TSLOPE=15.000000 -TCURVE=0.0100000 -THREL=15.000000
echo now trimming Mass Balance Index of $fieldname ${tile}
Trim_gdalwarp mbi
Delete_Temp_Files mbiA
Compress _mbi


#MultiScale Topographic Position Index ##########
echo now calculating MultiScale Topographic Position Index of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 28 -DEM=$working_dir/$tile/${tile}_s.sgrd -TPI=$working_dir/$tile/${tile}_tpiA.sgrd -SCALE_MIN=1 -SCALE_MAX=8 -SCALE_NUM=3
echo now trimming MultiScale Topographic Position Index of $fieldname ${tile}
Trim_gdalwarp tpi
Delete_Temp_Files tpiA
Compress _tpi


#MRVBF and MRRTF ##########
echo now calculating MRVBF and MRRTF of $fieldname ${tile} 
$SAGA_parallel ta_morphometry 8 -DEM=$working_dir/$tile/${tile}_s.sgrd -MRVBF=$working_dir/$tile/${tile}_mrvbfA.sgrd -MRRTF=$working_dir/$tile/${tile}_mrrtfA.sgrd -T_SLOPE=32 
echo now trimming MRVBF of $fieldname ${tile}
Trim_gdalwarp mrvbf
Delete_Temp_Files mrvbfA
Compress _mrvbf
	
echo now trimming MRRTF of $fieldname ${tile}
Trim_gdalwarp mrrtf
Delete_Temp_Files mrrtfA
Compress _mrrtf


#Saga wetness index, catchment area, modificed catchment area, and catchment slope ##########
echo now calculating Saga wetness index catchment area, modificed catchment area, and catchment slope of $fieldname ${tile} 
$SAGA_parallel ta_hydrology 15 -DEM=$working_dir/$tile/${tile}_s.sgrd -TWI=$working_dir/$tile/${tile}_swiA.sgrd -AREA=$working_dir/$tile/${tile}_caA.sgrd -AREA_MOD=$working_dir/$tile/${tile}_mcaA.sgrd -SLOPE=$working_dir/$tile/${tile}_csA.sgrd

echo now trimming Saga wetness index of $fieldname ${tile}
Trim_gdalwarp swi
Delete_Temp_Files swiA
Compress _swi

echo now trimming Catchment Slope of $fieldname ${tile}
Trim_gdalwarp cs
Delete_Temp_Files csA
Compress _cs

echo now trimming Modified Catchment Area of $fieldname ${tile}
Trim_gdalwarp mca
Delete_Temp_Files mcaA
Compress _mca

 
#Topographic wetness index - requires slope and catchment area as input ##########
#Re-calculate slope as it is needed in radians (this is very fast so no reason not to calculate twice)
$SAGA_parallel ta_morphometry 0 -ELEVATION=$working_dir/$tile/${tile}_s.sgrd -SLOPE=$working_dir/$tile/${tile}_slrA.sgrd -METHOD=1 -UNIT_SLOPE=0
echo now calculating topographic wetness index of $fieldname ${tile}
$SAGA_parallel ta_hydrology 20 -SLOPE=$working_dir/$tile/${tile}_slrA.sgrd -AREA=$working_dir/$tile/${tile}_caA.sgrd -TWI=$working_dir/$tile/${tile}_twiA.sgrd
echo now trimming topographic wetness index of $fieldname ${tile}
Trim_gdalwarp twi
Delete_Temp_Files twiA
Compress _twi
	
	
#Stream power index - requires slope (in radians) and catchment area as input ##########
echo now calculating stream power index of $fieldname ${tile}
$SAGA_parallel ta_hydrology 21 -SLOPE=$working_dir/$tile/${tile}_slrA.sgrd -AREA=$working_dir/$tile/${tile}_caA.sgrd -SPI=$working_dir/$tile/${tile}_spiA.sgrd
echo now trimming stream power index of $fieldname ${tile}
Trim_gdalwarp spi
Delete_Temp_Files spiA
Compress _spi


#LS factor - requires slope (must be in radians) and catchment area as input. 
echo now calculating LS Factor of $fieldname ${tile}
$SAGA_parallel ta_hydrology 22 -SLOPE=$working_dir/$tile/${tile}_slrA.sgrd -AREA=$working_dir/$tile/${tile}_caA.sgrd -LS=$working_dir/$tile/${tile}_lsA.sgrd -CONV=0 -METHOD=2 -EROSIVITY=1.000000 -STABILITY=0
echo now trimming LS Factor of $fieldname ${tile}
Trim_gdalwarp ls
Delete_Temp_Files lsA
Compress _ls

#Delete slope in radians (not needed after this calculation)
Delete_Temp_Files slrA


# Trim Catchment area (needed for twi, spi, and ls)		
echo now trimming Catchment Area index of $fieldname ${tile}
Trim_gdalwarp ca
Delete_Temp_Files caA		
Compress _ca


#Trim the smoothed DEM ##########
echo now trimming elevation of $fieldname ${tile}
#gdalwarp -multi -wo NUM_THREADS=$NumOfCore -cutline $indexB -cwhere "$fieldname = '${tile}'" -cblend $bufferB -crop_to_cutline  $working_dir/$tile/${tile}_s.sdat $working_dir/$tile/${tile}_s.tif
gdalwarp --config GDAL_CACHEMAX 500 -wm 500 -multi -wo NUM_THREADS=$NumOfCore -cutline $indexB -cwhere "$fieldname = '${tile}'" -cblend $bufferB -crop_to_cutline -tr 10 10  $working_dir/$tile/${tile}_s.sdat $working_dir/$tile/${tile}_s.tif
Delete_Temp_Files s
Compress _s

echo Start Time: $startTime
echo Finish Time: $(date +%F\ %H:%M:%S)
