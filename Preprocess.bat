@echo off
REM ********
rem batch file to preprocess DEM files before geoprocessing by area
rem author Colby W. Brungard PhD
REM Plant and Environmental Sciences Dept.  
REM New Mexico State University 
REM Las Cruces, NM 88003
REM cbrung@nmsu.edu
REM +1-575-646-1907
REM ********* (in case you are wondering; rem = remark)

REM modify the following paths to match your saga install and datafiles. This is currently set to run the test files included with this code.
rem 0. Set needed paths
rem path to saga_cmd.exe
set PATH=%PATH%;C:\saga-6.2.0_x64
SET SAGA_MLB=C:\saga-6.2.0_x64\tools

REM path to working dir
set WORK=c:\DEM

REM name of DEM to calculate derivatives from
set DEM=%WORK%\NM_5m_dtm.tif

REM path to watershed files. the shapefile and the dem MUST be in the same projection. If you want to re-project use the following:
rem ogr2ogr -t_srs EPSG:4326 testwatersheds_p.shp testwatersheds.shp
REM then use gdalinfo and ogrinfo to make sure that they match (they can appear different but GIS shows they are the same GCS).
set index=C:\DEM\wbdhu10_a_NM_JRN.shp

rem tiles are the names/values of each polygon. These must be manually input
set tiles=1303010305 1303010304

rem The column name of the shapefile attribute table with the HUC values
set fieldname=HUC10

rem Set a primary and secondary buffer distance. The primary will be used when clipping the DEM by watershed. The secondary will be used to trim off edge effects of each derivative before feathering the edges over this distance when mosaicing. The secondary buffer distance is 1/3 that of the primary buffer distance. 
set buffer=30

rem this results in a variable called %_buff2%. You do not need to change this unless you want to use a different fraction of the original buffer distance. In that case, change the number 3 to the desired fraction, for example if you only wanted to use 1/2 of the original buffer distance change this to 2. 
set /A "_buff2=%buffer%/3"


REM start time 
set startTime=%time%

REM 1. Clip DEM to shapefile with buffer, smooth and fill DEM, create analytical hillshade. I decided to smooth to remove artifacts. Note, it doesn't work to smooth and fill by watershed because it floods the DEM to the edges, so do this on the entire DEM.

REM REM Buffer and clip to shapefile
echo.
echo ^########## 
echo now clipping DEM to shapefile boundary
gdalwarp -cutline %index% -cblend %buffer% -crop_to_cutline -q %DEM% %WORK%\DEM.sdat

echo.
echo ^########## 
echo now smoothing DEM 
REM 3x3 (circle with radius of 2 cells) smoothing filter
saga_cmd grid_filter 0 -INPUT=%WORK%\DEM.sdat -RESULT=%WORK%\DEMs.sgrd -METHOD=0 -KERNEL_TYPE=1 -KERNEL_RADIUS=2

echo.
echo ^########## 
echo now filling sinks
REM Fill Sinks (Wang & Liu)
saga_cmd ta_preprocessor 5 -ELEV=%WORK%\DEMs.sgrd -FILLED=%WORK%\DEM_SF.sgrd -MINSLOPE=0.1 

echo.
echo ^########## 
echo now calculating analytical hillshade
REM analytical hillshade with standard defaults 
saga_cmd ta_lighting 0 -ELEVATION=%WORK%\DEM_SF.sgrd -SHADE=%WORK%\HSHADE.sgrd -METHOD=0 -AZIMUTH=315 -DECLINATION=45 -EXAGGERATION=1 

echo.
echo ^########## 
echo now converting smoothed and filled DEM and hillshade to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\DEM_SF.sgrd -FILE=%WORK%\ELEV.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\HSHADE.sgrd -FILE=%WORK%\HSHADE.tif

REM remove intermediate datasets
del %WORK%\DEM.sdat
del %WORK%\DEM.prj
del %WORK%\DEM.sgrd

del %WORK%\DEMs.mgrd
del %WORK%\DEMs.prj
del %WORK%\DEMs.sdat
del %WORK%\DEMs.sgrd
del %WORK%\DEMs.sdat.aux.xml

del %WORK%\HSHADE.mgrd
del %WORK%\HSHADE.prj
del %WORK%\HSHADE.sdat
del %WORK%\HSHADE.sgrd
del %WORK%\HSHADE.sdat.aux.xml


REM 2. Split DEM by watershed boundaries and write to individual file. Code modified from https://gis.stackexchange.com/questions/56842/how-to-clip-raster-by-multiple-polygons-in-multi-rasters
echo.
echo ^########## 
echo now splitting smoothed and filled DEM by watershed
echo %time%

REM make directories (md) for each watershed.
for %%a in (%tiles%) do (
 md %%a
 )

REM This chunck does the actual splitting
rem -cwhere: the field name in the shapefile that holds the tiles values
rem -cblend: buffer out X cells.

for %%a in (%tiles%) do (
 echo now subsetting %fieldname% %%a
   gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %buffer% -crop_to_cutline %WORK%\DEM_SF.sdat %2%%a\%%a.sgrd
  )
 
del %WORK%\DEM_SF.mgrd
del %WORK%\DEM_SF.prj
del %WORK%\DEM_SF.sdat
del %WORK%\DEM_SF.sgrd
del %WORK%\DEM_SF.sdat.aux.xml
