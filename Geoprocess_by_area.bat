@echo off
REM ********
rem batch file to calculate dem derivatives using gdal and saga gis
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
set DEM=%WORK%\testDEM2.tif

REM path to watershed files. the shapefile and the dem MUST be in the same projection. If you want to re-project use the following:
rem ogr2ogr -t_srs EPSG:4326 testwatersheds_p.shp testwatersheds.shp
REM then use gdalinfo and ogrinfo to make sure that they match (they can appear different but GIS shows they are the same GCS).
set index=C:\DEM\testwatersheds_p2.shp

rem tiles are the names/values of each polygon. These must be manually input
set tiles=130301030504 130301030505 130301030502

rem The column name of the shapefile attribute table with the HUC values
set fieldname=HUC12

rem Set a primary and secondary buffer distance. The primary will be used when clipping the DEM by watershed. The secondary will be used to trim off edge effects of each derivative before feathering the edges over this distance when mosaicing. The secondary buffer distance is 1/3 that of the primary buffer distance. 
set buffer=30
rem this results in a variable called %_buff2%. You do not need to change this unless you want to use a different fraction of the original buffer distance. In that case, change the number 3 to the desired fraction, for example if you only wanted to use 1/2 of the original buffer distance change this to 2. 
set /A "_buff2=%buffer%/3"

rem d=distance for the downslope distance gradient. Set to the resolution of your DEM
set d=5

REM To run this file: 
REM open OSGeo4W, navigate to the folder where this file and the base DEM are located, type the file name and hit enter


REM start time 
set startTime=%time%

REM 1. Clip DEM to shapefile with buffer, smooth and fill DEM, create analytical hillshade. I decided to smooth to remove artifacts. Note, it doesn't work to smooth and fill by watershed because it floods the DEM to the edges, so do this on the entire DEM.

REM Buffer and clip to shapefile
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
saga_cmd ta_lighting 0 -ELEVATION=%WORK%\DEM_SF.sgrd -SHADE=%WORK%\HSHADE.sgrd -METHOD=0 -AZIMUTH=315 -DECLINATION=45 -EXAGGERATION=1 

echo.
echo ^########## 
echo now converting smoothed and filled DEM and hillshade to .tif format
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\DEM_SF.sgrd -FILE=%WORK%\ELEV_SF.tif
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


REM 3. Calculate derivatives for each watershed, then trim these back to the original watershed area
REM the following script is one that is "embarrassingly parallel", but it runs rather quickly (I think that saga already does some parallelization), and I thought it too difficult to try and parallelize it. To do so, one would probably need to use the START command to initialize multiple cmd windows and run this entire script through them, but I'm not sure how one would figure out the number of cores to initialize, otherwise a loop would open as many processes as there are files. This is a problem if the # of files is > then the # of processors. 

REM I decided to include each calculation within it's own for loop. This is very inelegant, but it allows me to calculate a derivative for each watershed, stitch them all together, and then delete the individual derivatives for each watershed to save space (which was becoming an issue for large DEMs).


REM 3.1 TOOL Basic terrain parameters.  
FOR /D %%g IN (*) DO (
echo.
echo Now calculating basic terrain parameters for HUC %%g

REM Zevenbergen and Thorne 1987 method slope in percent
 saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd ^
 -SLOPE=%WORK%\%%g\%%g_SLOPE.sgrd ^
 -C_GENE=%WORK%\%%g\%%g_C_GENE.sgrd ^
 -C_PROF=%WORK%\%%g\%%g_C_PROF.sgrd ^
 -C_PLAN=%WORK%\%%g\%%g_C_PLAN.sgrd ^
 -C_TANG=%WORK%\%%g\%%g_C_TANG.sgrd ^
 -C_LONG=%WORK%\%%g\%%g_C_LONG.sgrd ^
 -C_CROS=%WORK%\%%g\%%g_C_CROS.sgrd ^
 -C_MINI=%WORK%\%%g\%%g_C_MINI.sgrd ^
 -C_MAXI=%WORK%\%%g\%%g_C_MAXI.sgrd ^
 -C_TOTA=%WORK%\%%g\%%g_C_TOTA.sgrd ^
 -C_ROTO=%WORK%\%%g\%%g_C_ROTO.sgrd ^
 -METHOD=6^
 -UNIT_SLOPE=2
)
  
 
echo.
echo ^########## 
echo now trimming derivatives to watershed boundaries
echo. 

REM Trim off the edges of each derivative by 20 cells (the original DEMs were extracted with a buffer of 30 cells, this trims the derivatives to only 10 cell overlap between watersheds) to remove edge artifacts.
for %%a in (%tiles%) do (

echo.
echo now trimming slope for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_SLOPE.sdat  %WORK%\%%a\%%a_SLOPEc.sgrd

echo.
echo now trimming General Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_GENE.sdat %WORK%\%%a\%%a_C_GENEc.sgrd

echo.
echo now trimming Profile Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_PROF.sdat %WORK%\%%a\%%a_C_PROFc.sgrd

echo.
echo now trimming Plan Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_PLAN.sdat %WORK%\%%a\%%a_C_PLANc.sgrd

echo.
echo now trimming Tangential Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_TANG.sdat %WORK%\%%a\%%a_C_TANGc.sgrd

echo.
echo now trimming Longitudinal Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_LONG.sdat %WORK%\%%a\%%a_C_LONGc.sgrd

echo.
echo now trimming Cross-Sectional Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_CROS.sdat %WORK%\%%a\%%a_C_CROSc.sgrd

echo.
echo now trimming Minimal Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_MINI.sdat %WORK%\%%a\%%a_C_MINIc.sgrd

echo.
echo now trimming Maximal Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_MAXI.sdat %WORK%\%%a\%%a_C_MAXIc.sgrd

echo.
echo now trimming Total Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_TOTA.sdat %WORK%\%%a\%%a_C_TOTAc.sgrd

echo.
echo now trimming Flow Line Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_ROTO.sdat %WORK%\%%a\%%a_C_ROTOc.sgrd
)
 
  
REM mosaic files. This uses a feathering distance of 10 cells so it should reduce cutline effects. 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing slope
set "files="                                                           
 for /r . %%g in (*SLOPEc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\SLOPE.sgrd

echo.                                                                  
echo ^##################                                               
echo Now mosaicing general curvature                                   
set "files="                                                           
 for /r . %%g in (*GENEc.sgrd) do call set files=%%files%%;%%g         
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_GENE.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing profile curvature                                   
set "files="                                                           
 for /r . %%g in (*C_PROFc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_PROF.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing plan curvature                                      
set "files="                                                           
 for /r . %%g in (*C_PLANc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_PLAN.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing tengential curvature                                
set "files="                                                           
 for /r . %%g in ( *C_TANGc.sgrd) do call set files=%%files%%;%%g      
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_TANG.sgrd  
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing longitudinal curvature                              
set "files="                                                           
 for /r . %%g in (*C_LONGc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=4 -TARGET_OUT_GRID=%WORK%\C_LONG.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing Cross-Sectional Curvature                           
set "files="                                                           
 for /r . %%g in (*C_CROSc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_CROS.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing Minimal Curvature                                   
set "files="                                                           
 for /r . %%g in (*C_MINIc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_MINI.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing Maximal Curvature                                   
set "files="                                                           
 for /r . %%g in (*C_MAXIc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_MAXI.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing Total Curvature                                     
set "files="                                                           
 for /r . %%g in (*C_TOTAc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_TOTA.sgrd
                                                                       
echo.                                                                  
echo ^##################                                               
echo Now mosaicing Flow Line Curvature                                 
set "files="                                                           
 for /r . %%g in (*C_ROTOc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_ROTO.sgrd
  
endlocal 

REM Convert to .tif format
echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\SLOPE.sgrd -FILE=%WORK%\SLOPE.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_GENE.sgrd -FILE=%WORK%\C_GENE.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_PROF.sgrd -FILE=%WORK%\C_PROF.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_PLAN.sgrd -FILE=%WORK%\C_PLAN.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_TANG.sgrd -FILE=%WORK%\C_TANG.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_LONG.sgrd -FILE=%WORK%\C_LONG.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_CROS.sgrd -FILE=%WORK%\C_CROS.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_MINI.sgrd -FILE=%WORK%\C_MINI.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_MAXI.sgrd -FILE=%WORK%\C_MAXI.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_TOTA.sgrd -FILE=%WORK%\C_TOTA.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_ROTO.sgrd -FILE=%WORK%\C_ROTO.tif
 
 
Remove individual files to reduce disk space 

del /S *SLOPE.sgrd
del /S *SLOPE.sdat
del /S *SLOPE.prj
del /S *SLOPE.mgrd
del /S *SLOPE.sdat.aux.xml
del /S *SLOPEc.sgrd

del /S *C_GENE.sgrd
del /S *C_GENE.sdat
del /S *C_GENE.prj
del /S *C_GENE.mgrd
del /S *C_GENE.sdat.aux.xml
del /S *C_GENEc.sgrd

del /S *C_PROF.sgrd
del /S *C_PROF.sdat
del /S *C_PROF.prj
del /S *C_PROF.mgrd
del /S *C_PROF.sdat.aux.xml
del /S *C_PROFc.sgrd

del /S *C_PLAN.sgrd
del /S *C_PLAN.sdat
del /S *C_PLAN.prj
del /S *C_PLAN.mgrd
del /S *C_PLAN.sdat.aux.xml
del /S *C_PLANc.sgrd

del /S *C_TANG.sgrd
del /S *C_TANG.sdat
del /S *C_TANG.prj
del /S *C_TANG.mgrd
del /S *C_TANG.sdat.aux.xml
del /S *C_TANGc.sgrd

del /S *C_LONG.sgrd
del /S *C_LONG.sdat
del /S *C_LONG.prj
del /S *C_LONG.mgrd
del /S *C_LONG.sdat.aux.xml
del /S *C_LONGc.sgrd

del /S *C_CROS.sgrd
del /S *C_CROS.sdat
del /S *C_CROS.prj
del /S *C_CROS.mgrd
del /S *C_CROS.sdat.aux.xml
del /S *C_CROSc.sgrd

del /S *C_MINI.sgrd
del /S *C_MINI.sdat
del /S *C_MINI.prj
del /S *C_MINI.mgrd
del /S *C_MINI.sdat.aux.xml
del /S *C_MINIc.sgrd

del /S *C_MAXI.sgrd
del /S *C_MAXI.sdat
del /S *C_MAXI.prj
del /S *C_MAXI.mgrd
del /S *C_MAXI.sdat.aux.xml
del /S *C_MAXIc.sgrd

del /S *C_TOTA.sgrd
del /S *C_TOTA.sdat
del /S *C_TOTA.prj
del /S *C_TOTA.mgrd
del /S *C_TOTA.sdat.aux.xml
del /S *C_TOTAc.sgrd

del /S *C_ROTO.sgrd
del /S *C_ROTO.sdat
del /S *C_ROTO.prj
del /S *C_ROTO.mgrd
del /S *C_ROTO.sdat.aux.xml
del /S *C_ROTOc.sgrd


REM 3.2 Convergence Index
FOR /D %%g IN (*) DO (
echo.
echo Now calculating Convergence Index for HUC %%g
saga_cmd ta_morphometry 1 -ELEVATION=%WORK%\%%g\%%g.sgrd -RESULT=%WORK%\%%g\%%g_CI.sgrd -METHOD=1 -NEIGHBOURS=1
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo.
echo now trimming convergence index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CI.sdat  %WORK%\%%a\%%a_CIc.sgrd
)
 
REM mosaic files.  
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing convergence index
set "files="                                                           
 for /r . %%g in (*CIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CI.sgrd 
endlocal 

REM Convert to .tif format
echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CI.sgrd -FILE=%WORK%\CI.tif
 
REM Remove intermediate files to reduce disk space 
del /S *CI.sgrd
del /S *CI.sdat
del /S *CI.prj
del /S *CI.mgrd
del /S *CI.sdat.aux.xml
del /S *CIc.sgrd


REM 3.3 Diurnal Anisotropic Heating - alpha = southwest angle 
FOR /D %%g IN (*) DO (
echo Now calculating Diurnal Anisotropic Heating Index for HUC %%g
saga_cmd ta_morphometry 12 -DEM=%WORK%\%%g\%%g.sgrd -DAH=%WORK%\%%g\%%g_DAH.sgrd -ALPHA_MAX=225
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming diurnal anisotropic heating index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_DAH.sdat  %WORK%\%%a\%%a_DAHc.sgrd
)
 
REM mosaic files. This uses a feathering distance of 10 cells so it should reduce cutline effects. 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing diurnal heating index
set "files="                                                           
 for /r . %%g in (*DAHc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\DAH.sgrd
endlocal 

REM Convert to .tif format
echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\DAH.sgrd -FILE=%WORK%\DAH.tif
 
REM Remove individual files to reduce disk space 
del /S *DAH.sgrd
del /S *DAH.sdat
del /S *DAH.prj
del /S *DAH.mgrd
del /S *DAH.sdat.aux.xml
del /S *DAHc.sgrd 


REM 3.3 Downslope Distance Gradient - how far downslope does one have to go to descend d meters?
rem http://onlinelibrary.wiley.com/doi/10.1029/2004WR003130/full - maybe useful for modeling soil depth, probably in humid environments.
rem distance = 5 since this is the resolution of the DEM. That seems logical to me. Output is gradient in degrees.
  
FOR /D %%g IN (*) DO (
echo Now calculating Downslope Distance Gradient for HUC %%g
saga_cmd ta_morphometry 9 -DEM=%WORK%\%%g\%%g.sgrd -GRADIENT=%WORK%\%%g\%%g_DDG.sgrd -DISTANCE=%d% -OUTPUT=2
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming Downslope Distance Gradient for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_DDG.sdat  %WORK%\%%a\%%a_DDGc.sgrd
)
 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing Downslope Distance Gradient
set "files="                                                           
 for /r . %%g in (*DDGc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\DDG.sgrd
endlocal 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\DDG.sgrd -FILE=%WORK%\DDG.tif
 
REM Remove individual files to reduce disk space 
del /S *DDG.sgrd
del /S *DDG.sdat
del /S *DDG.prj
del /S *DDG.mgrd
del /S *DDG.sdat.aux.xml
del /S *DDGc.sgrd 
 
 
REM 3.4 MultiScale Topographic Position Index, the defaults seemed fine to me
echo.
FOR /D %%g IN (*) DO (
echo Now calculating MultiScale Topographic Position Index for HUC %%g
saga_cmd ta_morphometry 28 -DEM=%WORK%\%%g\%%g.sgrd -TPI=%WORK%\%%g\%%g_TPI.sgrd -SCALE_MIN=1 -SCALE_MAX=8 -SCALE_NUM=3
) 
	 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming MultiScale Topographic Position Index  for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TPI.sdat %WORK%\%%a\%%a_TPIc.sgrd
)
  
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing MultiScale Topographic Position Index 
set "files="                                                           
 for /r . %%g in (*TPIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TPI.sgrd
endlocal 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\TPI.sgrd -FILE=%WORK%\TPI.tif
 
del /S *TPI.sgrd
del /S *TPI.sdat
del /S *TPI.prj
del /S *TPI.mgrd
del /S *TPI.sdat.aux.xml
del /S *TPIc.sgrd 
 

3.5 MRVBF http://onlinelibrary.wiley.com/doi/10.1029/2002WR001426/abstract
intended for separating erosional and depositional areas. Valley bottoms = depositional areas. MRVBF: higher values indicate that this is more likely a valley bottom. MRRTF: higher values indicate more likely a ridge. "While MRVBF is a continuous measure, it naturally divides into classes corresponding to the different resolutions and slope thresholds. Values less than 0.5 are not valley bottom areas. Values from 0.5 to 1.5 are considered to be the steepest and smallest resolvable valley bottoms for 25 m DEMs. Flatter and larger valley bottoms are represented by values from 1.5 to 2.5, 2.5 to 3.5, and so on"  
According to the paper, T_Slope was set to 44. This was chosen by fitting a power relationship between the resolution and the thresholds listed in paragraph 26 in the paper (the equation is y (t_slope) = 1659.51*(DEM resolution ^-0.819). All other parameters were left to default values as suggested by the paper (section 2.8).  

echo.
FOR /D %%g IN (*) DO (
echo Now calculating MRVBF and MRRTF for HUC %%g
  saga_cmd ta_morphometry 8 -DEM=%WORK%\%%g\%%g.sgrd -MRVBF=%WORK%\%%g\%%g_MRVBF.sgrd -MRRTF=%WORK%\%%g\%%g_MRRTF.sgrd -T_SLOPE=44 -T_PCTL_V=0.400000 -T_PCTL_R=0.350000 -P_SLOPE=4.000000 -P_PCTL=3.000000 -MAX_RES=100.0
) 
	 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming MRVBF and MRRTF  for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MRVBF.sdat %WORK%\%%a\%%a_MRVBFc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MRRTF.sdat %WORK%\%%a\%%a_MRRTFc.sgrd
)
  
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing MRVBF  
set "files="                                                           
 for /r . %%g in (*MRVBFc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MRVBF.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing MRRTF  
set "files="                                                           
 for /r . %%g in (*MRRTFc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MRRTF.sgrd
endlocal 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\MRVBF.sgrd -FILE=%WORK%\MRVBF.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\MRRTF.sgrd -FILE=%WORK%\MRRTF.tif
 
del /S *MRVBF.sgrd
del /S *MRVBF.sdat
del /S *MRVBF.prj
del /S *MRVBF.mgrd
del /S *MRVBF.sdat.aux.xml
del /S *MRVBFc.sgrd

del /S *MRRTF.sgrd
del /S *MRRTF.sdat
del /S *MRRTF.prj
del /S *MRRTF.mgrd
del /S *MRRTF.sdat.aux.xml
del /S *MRRTFc.sgrd


REM 3.6 Relative heights and slope positions. Didn't see much reason to change the default settings.  
FOR /D %%g IN (*) DO (
echo Now calculating relative heights and slope positions for HUC %%g
   saga_cmd ta_morphometry 14 -DEM=%WORK%\%%g\%%g.sgrd -HO=%WORK%\%%g\%%g_HO.sgrd -HU=%WORK%\%%g\%%g_HU.sgrd -NH=%WORK%\%%g\%%g_NH.sgrd -SH=%WORK%\%%g\%%g_SH.sgrd -MS=%WORK%\%%g\%%g_MS.sgrd -W=0.5 -T=10.0 -E=2.0 
) 
	 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming relative heights and slope positions for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_HO.sdat %WORK%\%%a\%%a_HOc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_HU.sdat %WORK%\%%a\%%a_HUc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_NH.sdat %WORK%\%%a\%%a_NHc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_SH.sdat %WORK%\%%a\%%a_SHc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MS.sdat %WORK%\%%a\%%a_MSc.sgrd
)
  
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing HO 
set "files="                                                           
 for /r . %%g in (*HOc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\HO.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing HU 
set "files="                                                           
 for /r . %%g in (*HUc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\HU.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing NH  
set "files="                                                           
 for /r . %%g in (*NHc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\NH.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing SH  
set "files="                                                           
 for /r . %%g in (*SHc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\SH.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing MS  
set "files="                                                           
 for /r . %%g in (*MSc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MS.sgrd
endlocal 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\HO.sgrd -FILE=%WORK%\HO.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\HU.sgrd -FILE=%WORK%\HU.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\NH.sgrd -FILE=%WORK%\NH.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\SH.sgrd -FILE=%WORK%\SH.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\MS.sgrd -FILE=%WORK%\MS.tif
 
del /S *HO.sgrd
del /S *HO.sdat
del /S *HO.prj
del /S *HO.mgrd
del /S *HO.sdat.aux.xml
del /S *HOc.sgrd

del /S *HU.sgrd
del /S *HU.sdat
del /S *HU.prj
del /S *HU.mgrd
del /S *HU.sdat.aux.xml
del /S *HUc.sgrd 

del /S *NH.sgrd
del /S *NH.sdat
del /S *NH.prj
del /S *NH.mgrd
del /S *NH.sdat.aux.xml
del /S *NHc.sgrd 

del /S *SH.sgrd
del /S *SH.sdat
del /S *SH.prj
del /S *SH.mgrd
del /S *SH.sdat.aux.xml
del /S *SHc.sgrd 

del /S *MS.sgrd
del /S *MS.sdat
del /S *MS.prj
del /S *MS.mgrd
del /S *MS.sdat.aux.xml
del /S *MSc.sgrd 
 
 
REM 3.7 Terrain Ruggedness Index. Which areas are the most rugged. "Calculates the sum change in elevation between a grid cell and its eight neighbor grid cells. I chose a radius of 10 cells (10x5 = 50m (or 100 m diameter)), and a circular mode. https://www.researchgate.net/publication/259011943_A_Terrain_Ruggedness_Index_that_Quantifies_Topographic_Heterogeneity 
FOR /D %%g IN (*) DO (
echo Now calculating terrain ruggedness index for HUC %%g
saga_cmd ta_morphometry 16 -DEM=%WORK%\%%g\%%g.sgrd -TRI=%WORK%\%%g\%%g_TRI.sgrd -MODE=1 -RADIUS=10
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming terrain ruggedness index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TRI.sdat  %WORK%\%%a\%%a_TRIc.sgrd
)
 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing terrain ruggedness index
set "files="                                                           
 for /r . %%g in (*TRIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TRI.sgrd
endlocal 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\TRI.sgrd -FILE=%WORK%\TRI.tif
 
REM Remove individual files to reduce disk space 
del /S *TRI.sgrd
del /S *TRI.sdat
del /S *TRI.prj
del /S *TRI.mgrd
del /S *TRI.sdat.aux.xml
del /S *TRIc.sgrd 

 
REM REM 3.8 Terrain Surface Convexity. Had to take the defaults since I couldn't get access to the paper. Probably a bad idea. Kernel 1 = eight neighborhood 
FOR /D %%g IN (*) DO (
echo Now calculating terrain surface convexity for HUC %%g
saga_cmd ta_morphometry 21 -DEM=%WORK%\%%g\%%g.sgrd -CONVEXITY=%WORK%\%%g\%%g_TSCV.sgrd -KERNEL=1 -TYPE=0 -EPSILON=0.0 -SCALE=10 -METHOD=1 -DW_WEIGHTING=3 -DW_BANDWIDTH=0.7
saga_cmd ta_morphometry 21 -DEM=%WORK%\%%g\%%g.sgrd -CONVEXITY=%WORK%\%%g\%%g_TSCC.sgrd -KERNEL=0 -TYPE=1 -EPSILON=0.0 -SCALE=10 -METHOD=1 -DW_WEIGHTING=3 -DW_BANDWIDTH=0.7
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming terrain surface convexity for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TSCV.sdat  %WORK%\%%a\%%a_TSCVc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TSCC.sdat  %WORK%\%%a\%%a_TSCCc.sgrd
)
 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing terrain surface convexity 
set "files="                                                           
 for /r . %%g in (*TSCVc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TSCV.sgrd
endlocal

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing terrain surface convexity 
set "files="                                                           
 for /r . %%g in (*TSCCc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TSCC.sgrd
endlocal
 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\TSCV.sgrd -FILE=%WORK%\TSCV.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\TSCC.sgrd -FILE=%WORK%\TSCC.tif
 
REM Remove individual files to reduce disk space 
del /S *TSCV.sgrd
del /S *TSCV.sdat
del /S *TSCV.prj
del /S *TSCV.mgrd
del /S *TSCV.sdat.aux.xml
del /S *TSCVc.sgrd 

del /S *TSCC.sgrd
del /S *TSCC.sdat
del /S *TSCC.prj
del /S *TSCC.mgrd
del /S *TSCC.sdat.aux.xml
del /S *TSCCc.sgrd

 
REM 3.9 Terrain Surface Texture
FOR /D %%g IN (*) DO (
echo Now calculating terrain surface texture for HUC %%g
saga_cmd ta_morphometry 20 -DEM=%WORK%\%%g\%%g.sgrd -TEXTURE=%WORK%\%%g\%%g_TST.sgrd -EPSILON=1.0 -SCALE=10 -METHOD=1 -DW_WEIGHTING=3 -DW_BANDWIDTH=0.7
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming terrain surface texture for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TST.sdat  %WORK%\%%a\%%a_TSTc.sgrd
)
 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing terrain surface texture
set "files="                                                           
 for /r . %%g in (*TSTc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TST.sgrd
endlocal 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\TST.sgrd -FILE=%WORK%\TST.tif
 
REM Remove individual files to reduce disk space 
del /S *TST.sgrd
del /S *TST.sdat
del /S *TST.prj
del /S *TST.mgrd
del /S *TST.sdat.aux.xml
del /S *TSTc.sgrd


REM 3.10 Upslope and downslope curvature. https://www.sciencedirect.com/science/article/pii/009830049190048I. Decided against using up and down local curvature since they weren't very different than up/down curvature. 
FOR /D %%g IN (*) DO (
echo Now calculating upslope and downslope curvature for HUC %%g
saga_cmd ta_morphometry 26 -DEM=%WORK%\%%g\%%g.sgrd -C_LOCAL=%WORK%\%%g\%%g_CL.sgrd -C_UP=%WORK%\%%g\%%g_CUP.sgrd -C_DOWN=%WORK%\%%g\%%g_CD.sgrd -WEIGHTING=0.5
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming upslope and downslope curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CL.sdat %WORK%\%%a\%%a_CLc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CUP.sdat %WORK%\%%a\%%a_CUPc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CD.sdat %WORK%\%%a\%%a_CDc.sgrd
)
 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing local curvature
set "files="                                                           
 for /r . %%g in (*CLc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CL.sgrd
endlocal

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing upslope curvature
set "files="                                                           
 for /r . %%g in (*CUPc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CUP.sgrd
endlocal

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing downslope curvature
set "files="                                                           
 for /r . %%g in (*CDc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CD.sgrd
endlocal

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CL.sgrd -FILE=%WORK%\CL.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\Cup.sgrd -FILE=%WORK%\CUP.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\CD.sgrd -FILE=%WORK%\CD.tif
 
REM Remove intermediate files to reduce disk space 
del /S *CL.sgrd
del /S *CL.sdat
del /S *CL.prj
del /S *CL.mgrd
del /S *CL.sdat.aux.xml
del /S *CLc.sgrd

del /S *Cup.sgrd
del /S *Cup.sdat
del /S *Cup.prj
del /S *Cup.mgrd
del /S *Cup.sdat.aux.xml
del /S *Cupc.sgrd

del /S *CD.sgrd
del /S *CD.sdat
del /S *CD.prj
del /S *CD.mgrd
del /S *CD.sdat.aux.xml
del /S *CDc.sgrd


REM 3.11 Saga wetness index. Kept defaults as is. 
FOR /D %%g IN (*) DO (
echo Now calculating saga wetness index for HUC %%g
saga_cmd ta_hydrology 15 -DEM=%WORK%\%%g\%%g.sgrd -AREA=%WORK%\%%g\%%g_CAR.sgrd -SLOPE=%WORK%\%%g\%%g_CSL.sgrd -AREA_MOD=%WORK%\%%g\%%g_MCA.sgrd -TWI=%WORK%\%%g\%%g_SWI.sgrd -SUCTION=10.000000 -AREA_TYPE=2 -SLOPE_TYPE=1 -SLOPE_MIN=0.0 -SLOPE_OFF=0.1 -SLOPE_WEIGHT=1.0
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming saga wetness index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CAR.sdat  %WORK%\%%a\%%a_CARc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CSL.sdat  %WORK%\%%a\%%a_CSLc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MCA.sdat  %WORK%\%%a\%%a_MCAc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_SWI.sdat  %WORK%\%%a\%%a_SWIc.sgrd
)
 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing catchment area
set "files="                                                           
 for /r . %%g in (*CARc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CAR.sgrd
endlocal

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing catchment slope
set "files="                                                           
 for /r . %%g in (*CSLc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CSL.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing modified catchment area
set "files="                                                           
 for /r . %%g in (*MCAc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MCA.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing saga wetness index
set "files="                                                           
 for /r . %%g in (*SWIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\SWI.sgrd
endlocal 
 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CAR.sgrd -FILE=%WORK%\CAR.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\CSL.sgrd -FILE=%WORK%\CSL.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\MCA.sgrd -FILE=%WORK%\MCA.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\SWI.sgrd -FILE=%WORK%\SWI.tif
 
REM Remove individual files to reduce disk space 
del /S *CAR.sgrd
del /S *CAR.sdat
del /S *CAR.prj
del /S *CAR.mgrd
del /S *CAR.sdat.aux.xml
del /S *CARc.sgrd

del /S *CSL.sgrd
del /S *CSL.sdat
del /S *CSL.prj
del /S *CSL.mgrd
del /S *CSL.sdat.aux.xml
del /S *CSLc.sgrd

del /S *MCA.sgrd
del /S *MCA.sdat
del /S *MCA.prj
del /S *MCA.mgrd
del /S *MCA.sdat.aux.xml
del /S *MCAc.sgrd

del /S *SWI.sgrd
del /S *SWI.sdat
del /S *SWI.prj
del /S *SWI.mgrd
del /S *SWI.sdat.aux.xml
del /S *SWIc.sgrd
 

REM 3.12 Topographic Openness- I'm not sure this makes much sense in an arid environment, but since it was intended to be input for OBIA geomorphological mapping I thought it might be interesting. 
FOR /D %%g IN (*) DO (
echo Now calculating terrain openness for HUC %%g
saga_cmd ta_lighting 5 -DEM=%WORK%\%%g\%%g.sgrd -POS=%WORK%\%%g\%%g_PO.sgrd -NEG=%WORK%\%%g\%%g_NO.sgrd -RADIUS=100 -METHOD=1 -DLEVEL=3.0 -NDIRS=8
)
 
echo ^########## 
for %%a in (%tiles%) do (
echo now trimming terrain openness for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_PO.sdat  %WORK%\%%a\%%a_POc.sgrd
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_NO.sdat  %WORK%\%%a\%%a_NOc.sgrd
)
 
setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing positive terrain openness
set "files="                                                           
 for /r . %%g in (*POc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\PO.sgrd
endlocal 

setlocal disableDelayedExpansion
echo.                                                                  
echo ^##################
echo Now mosaicing negative terrain openness
set "files="                                                           
 for /r . %%g in (*NOc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\NO.sgrd
endlocal 

echo.                                                                  
echo ^##################                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\PO.sgrd -FILE=%WORK%\PO.tif
saga_cmd io_gdal 2 -GRIDS=%WORK%\NO.sgrd -FILE=%WORK%\NO.tif
 
REM Remove individual files to reduce disk space 
del /S *PO.sgrd
del /S *PO.sdat
del /S *PO.prj
del /S *PO.mgrd
del /S *PO.sdat.aux.xml
del /S *POc.sgrd 

del /S *NO.sgrd
del /S *NO.sdat
del /S *NO.prj
del /S *NO.mgrd
del /S *NO.sdat.aux.xml
del /S *NOc.sgrd 


echo Start Time: %startTime%
echo Finish Time: %time%









 


