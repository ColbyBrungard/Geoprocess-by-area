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

REM the following script is one that is "embarrassingly parallel", but it runs rather quickly (I think that saga already does some parallelization), and I thought it too difficult to try and parallelize it. To do so, one would probably need to use the START command to initialize multiple cmd windows and run this entire script through them, but I'm not sure how one would figure out the number of cores to initialize, otherwise a loop would open as many processes as there are files. This is a problem if the # of files is > then the # of processors. 

REM I decided to include each calculation within it's own for loop. This is very inelegant, but it allows me to calculate a derivative for each watershed, stitch them all together, and then delete the individual derivatives for each watershed to save space (which quickly became an issue for large DEMs).

REM each code chunk (chunks start with ###########) follows the same format: 
REM 1. Calculate one DEM derivative for every DEM
REM 2. Trim off the edges of each derivative by a fraction of the original buffer to remove cells effected by edge artifacts
REM 3. Mosaic the derivative from every DEM into one file that covers the entire area
REM 4. Convert the .sgrd files to .tif files (easier to read in standard gis platforms)
REM 5. Remove intermediate .sgrd files to save space. 


echo ^##########
REM 1. Slope -Zevenbergen and Thorne 1987 method slope in percent
FOR /D %%g IN (*) DO (
echo Now deriving slope for %fieldname% %%g
saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -SLOPE=%WORK%\%%g\%%g_SLOPE.sgrd -METHOD=6 -UNIT_SLOPE=2
 )
 
for %%a in (%tiles%) do (
echo now trimming slope for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_SLOPE.sdat  %WORK%\%%a\%%a_SLOPEc.sgrd
)

echo Now mosaicing slope
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*SLOPEc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\SLOPE.sgrd
endlocal 
                                              
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\SLOPE.sgrd -FILE=%WORK%\SLOPE.tif

REM Remove intermediate files to reduce disk space 
del /S *SLOPE.sgrd
del /S *SLOPE.sdat
del /S *SLOPE.prj
del /S *SLOPE.mgrd
del /S *SLOPE.sdat.aux.xml
del /S *SLOPEc.sgrd




echo ^##########
REM 2. general curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving general curvature for %fieldname% %%g 
saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_GENE=%WORK%\%%g\%%g_C_GENE.sgrd -METHOD=6 -UNIT_SLOPE=2
) 

for %%a in (%tiles%) do (
echo now trimming General Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_GENE.sdat %WORK%\%%a\%%a_C_GENEc.sgrd
)

echo Now mosaicking general curvature  
setlocal disableDelayedExpansion                                                                               
set "files="                                                           
 for /r . %%g in (*GENEc.sgrd) do call set files=%%files%%;%%g         
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_GENE.sgrd
endlocal   
                                              
echo Now converting to .tif format 
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_GENE.sgrd -FILE=%WORK%\C_GENE.tif
 
REM Remove intermediate files to reduce disk space
del /S *C_GENE.sgrd
del /S *C_GENE.sdat
del /S *C_GENE.prj
del /S *C_GENE.mgrd
del /S *C_GENE.sdat.aux.xml
del /S *C_GENEc.sgrd




echo ^##########
REM 3. profile curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving profile curvature for %fieldname% %%g
saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_PROF=%WORK%\%%g\%%g_C_PROF.sgrd -METHOD=6 -UNIT_SLOPE=2
) 
 
for %%a in (%tiles%) do (
echo now trimming Profile Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_PROF.sdat %WORK%\%%a\%%a_C_PROFc.sgrd
)
 
echo Now mosaicing profile curvature  
setlocal disableDelayedExpansion                                                                               
set "files="                                                           
 for /r . %%g in (*C_PROFc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_PROF.sgrd
endlocal   

echo Now converting to .tif format  
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_PROF.sgrd -FILE=%WORK%\C_PROF.tif

REM Remove intermediate files to reduce disk space
del /S *C_PROF.sgrd
del /S *C_PROF.sdat
del /S *C_PROF.prj
del /S *C_PROF.mgrd
del /S *C_PROF.sdat.aux.xml
del /S *C_PROFc.sgrd




echo ^##########
REM 4. plan curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving plan curvature for %fieldname% %%g
saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_PLAN=%WORK%\%%g\%%g_C_PLAN.sgrd -METHOD=6 -UNIT_SLOPE=2
) 

for %%a in (%tiles%) do (
echo now trimming Plan Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_PLAN.sdat %WORK%\%%a\%%a_C_PLANc.sgrd
)

echo Now mosaicing plan curvature                                                                   
setlocal disableDelayedExpansion                                                                                 
set "files="                                                           
 for /r . %%g in (*C_PLANc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_PLAN.sgrd
endlocal   
                                               
echo Now converting to .tif format  
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_PLAN.sgrd -FILE=%WORK%\C_PLAN.tif  

REM Remove intermediate files to reduce disk space
del /S *C_PLAN.sgrd
del /S *C_PLAN.sdat
del /S *C_PLAN.prj
del /S *C_PLAN.mgrd
del /S *C_PLAN.sdat.aux.xml
del /S *C_PLANc.sgrd




echo ^##########
REM 5. tangential curvature  -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving tangential curvature for %fieldname% %%g
saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_TANG=%WORK%\%%g\%%g_C_TANG.sgrd -METHOD=6 -UNIT_SLOPE=2
 ) 

for %%a in (%tiles%) do (
echo now trimming Tangential Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_TANG.sdat %WORK%\%%a\%%a_C_TANGc.sgrd
)

echo Now mosaicing tengential curvature                                                                    
setlocal disableDelayedExpansion                                                                              
set "files="                                                           
 for /r . %%g in ( *C_TANGc.sgrd) do call set files=%%files%%;%%g      
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_TANG.sgrd
endlocal   
                                              
echo Now converting to .tif format  
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_TANG.sgrd -FILE=%WORK%\C_TANG.tif  

REM Remove intermediate files to reduce disk space
del /S *C_TANG.sgrd
del /S *C_TANG.sdat
del /S *C_TANG.prj
del /S *C_TANG.mgrd
del /S *C_TANG.sdat.aux.xml
del /S *C_TANGc.sgrd




echo ^##########
REM 6. longitudinal curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving longitudinal curvature for %fieldname% %%g 
 saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_LONG=%WORK%\%%g\%%g_C_LONG.sgrd -METHOD=6 -UNIT_SLOPE=2
) 

for %%a in (%tiles%) do (
echo now trimming Longitudinal Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_LONG.sdat %WORK%\%%a\%%a_C_LONGc.sgrd
)

echo Now mosaicing longitudinal curvature                                                                    
setlocal disableDelayedExpansion                                                                            
set "files="                                                           
 for /r . %%g in (*C_LONGc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=4 -TARGET_OUT_GRID=%WORK%\C_LONG.sgrd
endlocal   
                                             
echo Now converting to .tif format  
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_LONG.sgrd -FILE=%WORK%\C_LONG.tif

REM Remove intermediate files to reduce disk space
del /S *C_LONG.sgrd
del /S *C_LONG.sdat
del /S *C_LONG.prj
del /S *C_LONG.mgrd
del /S *C_LONG.sdat.aux.xml
del /S *C_LONGc.sgrd




echo ^##########
REM 7. cross-sectional curvature  -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo.
echo Now deriving cross-sectional curvature for %fieldname% %%g 
 saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_CROS=%WORK%\%%g\%%g_C_CROS.sgrd -METHOD=6 -UNIT_SLOPE=2
) 

for %%a in (%tiles%) do (
echo now trimming Cross-Sectional Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_CROS.sdat %WORK%\%%a\%%a_C_CROSc.sgrd
)

echo Now mosaicing Cross-Sectional Curvature                                                                  
setlocal disableDelayedExpansion                                                                         
set "files="                                                           
 for /r . %%g in (*C_CROSc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_CROS.sgrd
endlocal                                                                        
																	                                                
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_CROS.sgrd -FILE=%WORK%\C_CROS.tif

REM Remove intermediate files to reduce disk space
del /S *C_CROS.sgrd
del /S *C_CROS.sdat
del /S *C_CROS.prj
del /S *C_CROS.mgrd
del /S *C_CROS.sdat.aux.xml
del /S *C_CROSc.sgrd



echo ^##########
REM 8. minimum curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving minimum curvature for %fieldname% %%g 
 saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_MINI=%WORK%\%%g\%%g_C_MINI.sgrd -METHOD=6 -UNIT_SLOPE=2
) 
 
for %%a in (%tiles%) do (
echo now trimming Minimal Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_MINI.sdat %WORK%\%%a\%%a_C_MINIc.sgrd
)

echo Now mosaicing Minimal Curvature                                                                  
setlocal disableDelayedExpansion                                                                                 
set "files="                                                           
 for /r . %%g in (*C_MINIc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_MINI.sgrd
endlocal   

echo Now converting to .tif format  
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_MINI.sgrd -FILE=%WORK%\C_MINI.tif

REM Remove intermediate files to reduce disk space
del /S *C_MINI.sgrd
del /S *C_MINI.sdat
del /S *C_MINI.prj
del /S *C_MINI.mgrd
del /S *C_MINI.sdat.aux.xml
del /S *C_MINIc.sgrd




echo ^##########
REM 9. maximum curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving maximum curvature for %fieldname% %%g 
 saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_MAXI=%WORK%\%%g\%%g_C_MAXI.sgrd -METHOD=6 -UNIT_SLOPE=2
) 

for %%a in (%tiles%) do (
echo now trimming Maximal Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_MAXI.sdat %WORK%\%%a\%%a_C_MAXIc.sgrd
)

echo Now mosaicing Maximal Curvature                                                                   
setlocal disableDelayedExpansion                                              
set "files="                                                           
 for /r . %%g in (*C_MAXIc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_MAXI.sgrd
endlocal   

echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_MAXI.sgrd -FILE=%WORK%\C_MAXI.tif

REM Remove intermediate files to reduce disk space
del /S *C_MAXI.sgrd
del /S *C_MAXI.sdat
del /S *C_MAXI.prj
del /S *C_MAXI.mgrd
del /S *C_MAXI.sdat.aux.xml
del /S *C_MAXIc.sgrd

  


echo ^##########
REM 10. total curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving total curvature for %fieldname% %%g 
 saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_TOTA=%WORK%\%%g\%%g_C_TOTA.sgrd -METHOD=6 -UNIT_SLOPE=2
) 
 
for %%a in (%tiles%) do (
echo now trimming Total Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_TOTA.sdat %WORK%\%%a\%%a_C_TOTAc.sgrd
)

echo Now mosaicing Total Curvature                                                                  
setlocal disableDelayedExpansion                                              
set "files="                                                           
 for /r . %%g in (*C_TOTAc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_TOTA.sgrd
endlocal   

echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_TOTA.sgrd -FILE=%WORK%\C_TOTA.tif

REM Remove intermediate files to reduce disk space
del /S *C_TOTA.sgrd
del /S *C_TOTA.sdat
del /S *C_TOTA.prj
del /S *C_TOTA.mgrd
del /S *C_TOTA.sdat.aux.xml
del /S *C_TOTAc.sgrd




echo ^##########
REM 11. Flow line (roto) curvature -Zevenbergen and Thorne 1987 method
FOR /D %%g IN (*) DO (
echo Now deriving flow line curvature for %fieldname% %%g 
 saga_cmd ta_morphometry 0 -ELEVATION=%WORK%\%%g\%%g.sgrd -C_ROTO=%WORK%\%%g\%%g_C_ROTO.sgrd -METHOD=6 -UNIT_SLOPE=2
) 

for %%a in (%tiles%) do (
echo now trimming Flow Line Curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_C_ROTO.sdat %WORK%\%%a\%%a_C_ROTOc.sgrd
)

echo Now mosaicing Flow Line Curvature                                                              
setlocal disableDelayedExpansion                                              
set "files="                                                           
 for /r . %%g in (*C_ROTOc.sgrd) do call set files=%%files%%;%%g       
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\C_ROTO.sgrd
endlocal 

echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\C_ROTO.sgrd -FILE=%WORK%\C_ROTO.tif

REM Remove intermediate files to reduce disk spac
del /S *C_ROTO.sgrd
del /S *C_ROTO.sdat
del /S *C_ROTO.prj
del /S *C_ROTO.mgrd
del /S *C_ROTO.sdat.aux.xml
del /S *C_ROTOc.sgrd 
 


echo ^########## 
REM 12. Convergence Index
FOR /D %%g IN (*) DO (
echo.
echo Now calculating Convergence Index for %fieldname% %%g
saga_cmd ta_morphometry 1 -ELEVATION=%WORK%\%%g\%%g.sgrd -RESULT=%WORK%\%%g\%%g_CI.sgrd -METHOD=1 -NEIGHBOURS=1
)
 
for %%a in (%tiles%) do (
echo.
echo now trimming convergence index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CI.sdat  %WORK%\%%a\%%a_CIc.sgrd
)
 
echo Now mosaicing convergence index  
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*CIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CI.sgrd 
endlocal 
                                            
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CI.sgrd -FILE=%WORK%\CI.tif
 
REM Remove intermediate files to reduce disk space 
del /S *CI.sgrd
del /S *CI.sdat
del /S *CI.prj
del /S *CI.mgrd
del /S *CI.sdat.aux.xml
del /S *CIc.sgrd


echo ^########## 
REM 13. Diurnal Anisotropic Heating - alpha = southwest angle 
FOR /D %%g IN (*) DO (
echo Now calculating Diurnal Anisotropic Heating Index for %fieldname% %%g
saga_cmd ta_morphometry 12 -DEM=%WORK%\%%g\%%g.sgrd -DAH=%WORK%\%%g\%%g_DAH.sgrd -ALPHA_MAX=225
)
 
for %%a in (%tiles%) do (
echo now trimming diurnal anisotropic heating index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_DAH.sdat  %WORK%\%%a\%%a_DAHc.sgrd
)
 
echo Now mosaicing diurnal heating index
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*DAHc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\DAH.sgrd
endlocal 
                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\DAH.sgrd -FILE=%WORK%\DAH.tif
 
REM Remove individual files to reduce disk space 
del /S *DAH.sgrd
del /S *DAH.sdat
del /S *DAH.prj
del /S *DAH.mgrd
del /S *DAH.sdat.aux.xml
del /S *DAHc.sgrd 



echo ^##########  
REM 14. MultiScale Topographic Position Index, the defaults seemed fine to me
FOR /D %%g IN (*) DO (
echo Now calculating MultiScale Topographic Position Index for %fieldname% %%g
saga_cmd ta_morphometry 28 -DEM=%WORK%\%%g\%%g.sgrd -TPI=%WORK%\%%g\%%g_TPI.sgrd -SCALE_MIN=1 -SCALE_MAX=8 -SCALE_NUM=3
) 
	  
for %%a in (%tiles%) do (
echo now trimming MultiScale Topographic Position Index  for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TPI.sdat %WORK%\%%a\%%a_TPIc.sgrd
)

echo Now mosaicing MultiScale Topographic Position Index  
setlocal disableDelayedExpansion 
set "files="                                                           
 for /r . %%g in (*TPIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TPI.sgrd
endlocal 

echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\TPI.sgrd -FILE=%WORK%\TPI.tif

REM Remove individual files to reduce disk space 
del /S *TPI.sgrd
del /S *TPI.sdat
del /S *TPI.prj
del /S *TPI.mgrd
del /S *TPI.sdat.aux.xml
del /S *TPIc.sgrd 


 
echo ^########## 
REM 15 MRVBF http://onlinelibrary.wiley.com/doi/10.1029/2002WR001426/abstract
REM intended for separating erosional and depositional areas. Valley bottoms = depositional areas. MRVBF: higher values indicate that this is more likely a valley bottom. MRRTF: higher values indicate more likely a ridge. "While MRVBF is a continuous measure, it naturally divides into classes corresponding to the different resolutions and slope thresholds. Values less than 0.5 are not valley bottom areas. Values from 0.5 to 1.5 are considered to be the steepest and smallest resolvable valley bottoms for 25 m DEMs. Flatter and larger valley bottoms are represented by values from 1.5 to 2.5, 2.5 to 3.5, and so on"  
REM According to the paper, T_Slope was set to 44. This was chosen by fitting a power relationship between the resolution and the thresholds listed in paragraph 26 in the paper (the equation is y (t_slope) = 1659.51*(DEM resolution ^-0.819). All other parameters were left to default values as suggested by the paper (section 2.8).  
FOR /D %%g IN (*) DO (
echo Now calculating MRVBF for %fieldname% %%g
saga_cmd ta_morphometry 8 -DEM=%WORK%\%%g\%%g.sgrd -MRVBF=%WORK%\%%g\%%g_MRVBF.sgrd -T_SLOPE=44 -T_PCTL_V=0.400000 -T_PCTL_R=0.350000 -P_SLOPE=4.000000 -P_PCTL=3.000000 -MAX_RES=100.0
) 
	 
for %%a in (%tiles%) do (
echo now trimming MRVBF for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MRVBF.sdat %WORK%\%%a\%%a_MRVBFc.sgrd
)

echo Now mosaicing MRVBF    
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*MRVBFc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MRVBF.sgrd
endlocal 
                                            
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\MRVBF.sgrd -FILE=%WORK%\MRVBF.tif
 
del /S *MRVBF.sgrd
del /S *MRVBF.sdat
del /S *MRVBF.prj
del /S *MRVBF.mgrd
del /S *MRVBF.sdat.aux.xml
del /S *MRVBFc.sgrd


echo ^##########
REM 16 MRRTF MRVBF http://onlinelibrary.wiley.com/doi/10.1029/2002WR001426/abstract
REM intended for separating erosional and depositional areas. MRRTF: higher values indicate more likely a ridge.
FOR /D %%g IN (*) DO (
echo Now calculating MRRTF for %fieldname% %%g
saga_cmd ta_morphometry 8 -DEM=%WORK%\%%g\%%g.sgrd -MRRTF=%WORK%\%%g\%%g_MRRTF.sgrd -T_SLOPE=44 -T_PCTL_V=0.400000 -T_PCTL_R=0.350000 -P_SLOPE=4.000000 -P_PCTL=3.000000 -MAX_RES=100.0
) 
	 
for %%a in (%tiles%) do (
echo now trimming MRRTF  for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MRRTF.sdat %WORK%\%%a\%%a_MRRTFc.sgrd
) 

echo Now mosaicing MRRTF
setlocal disableDelayedExpansion  
set "files="                                                           
 for /r . %%g in (*MRRTFc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MRRTF.sgrd
endlocal 
                                         
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\MRRTF.sgrd -FILE=%WORK%\MRRTF.tif

del /S *MRRTF.sgrd
del /S *MRRTF.sdat
del /S *MRRTF.prj
del /S *MRRTF.mgrd
del /S *MRRTF.sdat.aux.xml
del /S *MRRTFc.sgrd





echo ^##########
REM 17. Slope Height. Didn't see much reason to change the default settings.  
FOR /D %%g IN (*) DO (
echo Now calculating slope height for %fieldname% %%g
saga_cmd ta_morphometry 14 -DEM=%WORK%\%%g\%%g.sgrd -HO=%WORK%\%%g\%%g_HO.sgrd -W=0.5 -T=10.0 -E=2.0 
) 
	 
for %%a in (%tiles%) do (
echo now trimming slope height for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_HO.sdat %WORK%\%%a\%%a_HOc.sgrd
)

echo Now mosaicing slope height  
setlocal disableDelayedExpansion 
set "files="                                                           
 for /r . %%g in (*HOc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\HO.sgrd
endlocal 
                                               
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\HO.sgrd -FILE=%WORK%\HO.tif
 
del /S *HO.sgrd
del /S *HO.sdat
del /S *HO.prj
del /S *HO.mgrd
del /S *HO.sdat.aux.xml
del /S *HOc.sgrd



echo ^##########
REM 18. Valley Depth. Didn't see much reason to change the default settings.
FOR /D %%g IN (*) DO (
echo Now calculating valley depth for %fieldname% %%g
saga_cmd ta_morphometry 14 -DEM=%WORK%\%%g\%%g.sgrd -HU=%WORK%\%%g\%%g_HU.sgrd -W=0.5 -T=10.0 -E=2.0 
)
 
for %%a in (%tiles%) do (
echo now trimming valley depth for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_HU.sdat %WORK%\%%a\%%a_HUc.sgrd
)

echo Now mosaicing valley depth 
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*HUc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\HU.sgrd
endlocal 
                                              
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\HU.sgrd -FILE=%WORK%\HU.tif

del /S *HU.sgrd
del /S *HU.sdat
del /S *HU.prj
del /S *HU.mgrd
del /S *HU.sdat.aux.xml
del /S *HUc.sgrd 




echo ^##########
REM 19. Normalized Height. Didn't see much reason to change the default settings.
FOR /D %%g IN (*) DO (
echo Now calculating normalized height for %fieldname% %%g
saga_cmd ta_morphometry 14 -DEM=%WORK%\%%g\%%g.sgrd -NH=%WORK%\%%g\%%g_NH.sgrd -W=0.5 -T=10.0 -E=2.0 
) 

for %%a in (%tiles%) do (
echo now trimming normalized height for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_NH.sdat %WORK%\%%a\%%a_NHc.sgrd
)

echo Now mosaicing normalized height 
setlocal disableDelayedExpansion 
set "files="                                                           
 for /r . %%g in (*NHc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\NH.sgrd
endlocal 
                                              
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\NH.sgrd -FILE=%WORK%\NH.tif

del /S *NH.sgrd
del /S *NH.sdat
del /S *NH.prj
del /S *NH.mgrd
del /S *NH.sdat.aux.xml
del /S *NHc.sgrd 




echo ^##########
REM 20. Standardized Height. Didn't see much reason to change the default settings.
FOR /D %%g IN (*) DO (
echo Now calculating standardized heights for %fieldname% %%g
saga_cmd ta_morphometry 14 -DEM=%WORK%\%%g\%%g.sgrd -SH=%WORK%\%%g\%%g_SH.sgrd -W=0.5 -T=10.0 -E=2.0 
) 

for %%a in (%tiles%) do (
echo now trimming standardized height for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_SH.sdat %WORK%\%%a\%%a_SHc.sgrd
)

echo Now mosaicing standardized height 
setlocal disableDelayedExpansion 
set "files="                                                           
 for /r . %%g in (*SHc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\SH.sgrd
endlocal 
                                              
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\SH.sgrd -FILE=%WORK%\SH.tif

del /S *SH.sgrd
del /S *SH.sdat
del /S *SH.prj
del /S *SH.mgrd
del /S *SH.sdat.aux.xml
del /S *SHc.sgrd




echo ^##########
REM 21. Mid-slope position. Didn't see much reason to change the default settings.
FOR /D %%g IN (*) DO (
echo Now calculating mid-slope position for %fieldname% %%g
saga_cmd ta_morphometry 14 -DEM=%WORK%\%%g\%%g.sgrd -MS=%WORK%\%%g\%%g_MS.sgrd -W=0.5 -T=10.0 -E=2.0 
) 

for %%a in (%tiles%) do (
echo now trimming mid-slope position for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MS.sdat %WORK%\%%a\%%a_MSc.sgrd
)

echo Now mosaicing mid-slope position 
setlocal disableDelayedExpansion 
set "files="                                                           
 for /r . %%g in (*MSc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MS.sgrd
endlocal 
                                              
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\MS.sgrd -FILE=%WORK%\MS.tif


del /S *MS.sgrd
del /S *MS.sdat
del /S *MS.prj
del /S *MS.mgrd
del /S *MS.sdat.aux.xml
del /S *MSc.sgrd 



echo ^##########
REM 22 Terrain Ruggedness Index. Which areas are the most rugged. "Calculates the sum change in elevation between a grid cell and its eight neighbor grid cells. I chose a radius of 10 cells (10x5 = 50m (or 100 m diameter)), and a circular mode. https://www.researchgate.net/publication/259011943_A_Terrain_Ruggedness_Index_that_Quantifies_Topographic_Heterogeneity
FOR /D %%g IN (*) DO (
echo Now deriving calculating terrain ruggedness index for %fieldname% %%g
saga_cmd ta_morphometry 16 -DEM=%WORK%\%%g\%%g.sgrd -TRI=%WORK%\%%g\%%g_TRI.sgrd -MODE=1 -RADIUS=10 
 )

for %%a in (%tiles%) do (
echo now trimming Terrain Ruggedness Index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TRI.sdat  %WORK%\%%a\%%a_TRIc.sgrd
)

echo Now mosaicing Terrain Ruggedness Index
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*TRIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TRI.sgrd
endlocal 
                                             
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\TRI.sgrd -FILE=%WORK%\TRI.tif

REM Remove intermediate files to reduce disk space 
del /S *TRI.sgrd
del /S *TRI.sdat
del /S *TRI.prj
del /S *TRI.mgrd
del /S *TRI.sdat.aux.xml
del /S *TRIc.sgrd 




echo ^##########
REM 23. Terrain Surface Convexity. Had to take the defaults since I couldn't get access to the paper. Probably a bad idea. Kernel 1 = eight neighborhood 
FOR /D %%g IN (*) DO (
echo Now deriving terrain surface convexity for %fieldname% %%g
saga_cmd ta_morphometry 21 -DEM=%WORK%\%%g\%%g.sgrd -CONVEXITY=%WORK%\%%g\%%g_TSCV.sgrd -KERNEL=1 -TYPE=0 -EPSILON=0.0 -SCALE=10 -METHOD=1 -DW_WEIGHTING=3 -DW_BANDWIDTH=0.7
 )
 
for %%a in (%tiles%) do (
echo now trimming terrain surface convexity for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_TSCV.sdat  %WORK%\%%a\%%a_TSCVc.sgrd
)

echo Now mosaicing terrain surface convexity 
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*TSCVc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\TSCV.sgrd
endlocal 

echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\TSCV.sgrd -FILE=%WORK%\TSCV.tif

REM Remove intermediate files to reduce disk space 
del /S *TSCV.sgrd
del /S *TSCV.sdat
del /S *TSCV.prj
del /S *TSCV.mgrd
del /S *TSCV.sdat.aux.xml
del /S *TSCVc.sgrd 
 
 
 

echo ^########## 
REM 24 Local curvature. https://www.sciencedirect.com/science/article/pii/009830049190048I. Decided against using up and down local curvature since they weren't very different than up/down curvature. 
FOR /D %%g IN (*) DO (
echo Now calculating local curvature for %fieldname% %%g
saga_cmd ta_morphometry 26 -DEM=%WORK%\%%g\%%g.sgrd -C_LOCAL=%WORK%\%%g\%%g_CL.sgrd -WEIGHTING=0.5
)
 
for %%a in (%tiles%) do (
echo now trimming local curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CL.sdat %WORK%\%%a\%%a_CLc.sgrd
)

echo Now mosaicing local curvature 
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*CLc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CL.sgrd
endlocal
                                              
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CL.sgrd -FILE=%WORK%\CL.tif
 
REM Remove intermediate files to reduce disk space 
del /S *CL.sgrd
del /S *CL.sdat
del /S *CL.prj
del /S *CL.mgrd
del /S *CL.sdat.aux.xml
del /S *CLc.sgrd


echo ^##########
REM 25 Upslope curvature. https://www.sciencedirect.com/science/article/pii/009830049190048I. Decided against using up and down local curvature since they weren't very different than up/down curvature. 
FOR /D %%g IN (*) DO (
echo Now calculating upslope curvature for %fieldname% %%g
saga_cmd ta_morphometry 26 -DEM=%WORK%\%%g\%%g.sgrd -C_UP=%WORK%\%%g\%%g_CUP.sgrd -WEIGHTING=0.5
)
 
for %%a in (%tiles%) do (
echo now trimming upslope curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CUP.sdat %WORK%\%%a\%%a_CUPc.sgrd
)

echo Now mosaicing upslope curvature
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*CUPc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CUP.sgrd
endlocal
                                          
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\Cup.sgrd -FILE=%WORK%\CUP.tif
 
REM Remove intermediate files to reduce disk space 
del /S *Cup.sgrd
del /S *Cup.sdat
del /S *Cup.prj
del /S *Cup.mgrd
del /S *Cup.sdat.aux.xml
del /S *Cupc.sgrd


echo ^########## 
REM 26 Downslope curvature. https://www.sciencedirect.com/science/article/pii/009830049190048I. Decided against using up and down local curvature since they weren't very different than up/down curvature. 
FOR /D %%g IN (*) DO (
echo Now calculating downslope curvature for %fieldname% %%g
saga_cmd ta_morphometry 26 -DEM=%WORK%\%%g\%%g.sgrd -C_DOWN=%WORK%\%%g\%%g_CD.sgrd -WEIGHTING=0.5
)
 
for %%a in (%tiles%) do (
echo now trimming downslope curvature for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CD.sdat %WORK%\%%a\%%a_CDc.sgrd
)

echo Now mosaicing downslope curvature
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*CDc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CD.sgrd
endlocal
                                         
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CD.sgrd -FILE=%WORK%\CD.tif

REM Remove intermediate files to reduce disk space 
del /S *CD.sgrd
del /S *CD.sdat
del /S *CD.prj
del /S *CD.mgrd
del /S *CD.sdat.aux.xml
del /S *CDc.sgrd



echo ^########## 
REM 27 Saga wetness index. Kept defaults as is. 
FOR /D %%g IN (*) DO (
echo Now calculating saga wetness index for %fieldname% %%g
saga_cmd ta_hydrology 15 -DEM=%WORK%\%%g\%%g.sgrd -TWI=%WORK%\%%g\%%g_SWI.sgrd -SUCTION=10.000000 -AREA_TYPE=2 -SLOPE_TYPE=1 -SLOPE_MIN=0.0 -SLOPE_OFF=0.1 -SLOPE_WEIGHT=1.0
)
 
for %%a in (%tiles%) do (
echo now trimming saga wetness index for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_SWI.sdat  %WORK%\%%a\%%a_SWIc.sgrd
)

echo Now mosaicing saga wetness index 
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*SWIc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\SWI.sgrd
endlocal 
 
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\SWI.sgrd -FILE=%WORK%\SWI.tif
 
REM Remove individual files to reduce disk space 
del /S *SWI.sgrd
del /S *SWI.sdat
del /S *SWI.prj
del /S *SWI.mgrd
del /S *SWI.sdat.aux.xml
del /S *SWIc.sgrd
 

echo ^########## 
REM 28 catchment area. Kept defaults as is. 
FOR /D %%g IN (*) DO (
echo Now calculating catchment area for %fieldname% %%g
saga_cmd ta_hydrology 15 -DEM=%WORK%\%%g\%%g.sgrd -AREA=%WORK%\%%g\%%g_CAR.sgrd -SUCTION=10.000000 -AREA_TYPE=2 -SLOPE_TYPE=1 -SLOPE_MIN=0.0 -SLOPE_OFF=0.1 -SLOPE_WEIGHT=1.0
)
  
for %%a in (%tiles%) do (
echo now trimming catchment area for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CAR.sdat  %WORK%\%%a\%%a_CARc.sgrd
)

echo Now mosaicing catchment area 
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*CARc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CAR.sgrd
endlocal
                                         
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CAR.sgrd -FILE=%WORK%\CAR.tif
 
REM Remove individual files to reduce disk space 
del /S *CAR.sgrd
del /S *CAR.sdat
del /S *CAR.prj
del /S *CAR.mgrd
del /S *CAR.sdat.aux.xml
del /S *CARc.sgrd
 
 
echo ^##########
REM 29 Catchment Slope. Kept defaults as is. 
FOR /D %%g IN (*) DO (
echo Now calculating saga wetness index for %fieldname% %%g
saga_cmd ta_hydrology 15 -DEM=%WORK%\%%g\%%g.sgrd -SLOPE=%WORK%\%%g\%%g_CSL.sgrd -SUCTION=10.000000 -AREA_TYPE=2 -SLOPE_TYPE=1 -SLOPE_MIN=0.0 -SLOPE_OFF=0.1 -SLOPE_WEIGHT=1.0
)
 
for %%a in (%tiles%) do (
echo now trimming catchment slope for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_CSL.sdat  %WORK%\%%a\%%a_CSLc.sgrd
)

echo Now mosaicing catchment slope 
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*CSLc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\CSL.sgrd
endlocal 

echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\CSL.sgrd -FILE=%WORK%\CSL.tif

 
REM Remove individual files to reduce disk space 
del /S *CSL.sgrd
del /S *CSL.sdat
del /S *CSL.prj
del /S *CSL.mgrd
del /S *CSL.sdat.aux.xml
del /S *CSLc.sgrd

 

REM 30 modified catchment area. Kept defaults as is. 
FOR /D %%g IN (*) DO (
echo Now calculating modified catchment area for %fieldname% %%g
saga_cmd ta_hydrology 15 -DEM=%WORK%\%%g\%%g.sgrd -AREA_MOD=%WORK%\%%g\%%g_MCA.sgrd -SUCTION=10.000000 -AREA_TYPE=2 -SLOPE_TYPE=1 -SLOPE_MIN=0.0 -SLOPE_OFF=0.1 -SLOPE_WEIGHT=1.0
)
 
for %%a in (%tiles%) do (
echo now trimming modified catchment area for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_MCA.sdat  %WORK%\%%a\%%a_MCAc.sgrd
)

echo Now mosaicing modified catchment area  
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*MCAc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\MCA.sgrd
endlocal 
  
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\MCA.sgrd -FILE=%WORK%\MCA.tif

REM Remove individual files to reduce disk space 
del /S *MCA.sgrd
del /S *MCA.sdat
del /S *MCA.prj
del /S *MCA.mgrd
del /S *MCA.sdat.aux.xml
del /S *MCAc.sgrd
 
 
 
echo ^########## 
REM 31 Positive Topographic Openness- I'm not sure this makes much sense in an arid environment, but since it was intended to be input for OBIA geomorphological mapping I thought it might be interesting. 
FOR /D %%g IN (*) DO (
echo Now calculating positive terrain openness for %fieldname% %%g
saga_cmd ta_lighting 5 -DEM=%WORK%\%%g\%%g.sgrd -POS=%WORK%\%%g\%%g_PO.sgrd -RADIUS=100 -METHOD=1 -DLEVEL=3.0 -NDIRS=8
)
 
for %%a in (%tiles%) do (
echo now trimming positive terrain openness for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_PO.sdat  %WORK%\%%a\%%a_POc.sgrd
)

echo Now mosaicing positive terrain openness
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*POc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\PO.sgrd
endlocal 

echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\PO.sgrd -FILE=%WORK%\PO.tif

REM Remove individual files to reduce disk space 
del /S *PO.sgrd
del /S *PO.sdat
del /S *PO.prj
del /S *PO.mgrd
del /S *PO.sdat.aux.xml
del /S *POc.sgrd 


echo ^########## 
REM 32 Negative Topographic Openness- I'm not sure this makes much sense in an arid environment, but since it was intended to be input for OBIA geomorphological mapping I thought it might be interesting. 
FOR /D %%g IN (*) DO (
echo Now calculating negative terrain openness for %fieldname% %%g
saga_cmd ta_lighting 5 -DEM=%WORK%\%%g\%%g.sgrd -NEG=%WORK%\%%g\%%g_NO.sgrd -RADIUS=100 -METHOD=1 -DLEVEL=3.0 -NDIRS=8
)
 
for %%a in (%tiles%) do (
echo now trimming terrain openness for %fieldname% %%a
gdalwarp -cutline %index% -cwhere "%fieldname% = '%%a'" -cblend %_buff2% -crop_to_cutline %WORK%\%%a\%%a_NO.sdat  %WORK%\%%a\%%a_NOc.sgrd
)

echo Now mosaicing negative terrain openness
setlocal disableDelayedExpansion
set "files="                                                           
 for /r . %%g in (*NOc.sgrd) do call set files=%%files%%;%%g  
  saga_cmd grid_tools 3 -GRIDS="%files%" -TYPE=9 -RESAMPLING=3 -OVERLAP=6 -BLEND_DIST=%_buff2% -TARGET_OUT_GRID=%WORK%\NO.sgrd
endlocal 
                                              
echo Now converting to .tif format
saga_cmd io_gdal 2 -GRIDS=%WORK%\NO.sgrd -FILE=%WORK%\NO.tif

REM Remove individual files to reduce disk space 
del /S *NO.sgrd
del /S *NO.sdat
del /S *NO.prj
del /S *NO.mgrd
del /S *NO.sdat.aux.xml
del /S *NOc.sgrd 

echo Start Time: %startTime%
echo Finish Time: %time%

REM this took 23 hours +- 5 min. 






REM Block template for each covariate

REM echo ^##########
REM REM 1. X
REM FOR /D %%g IN (*) DO (
REM echo.
REM echo Now deriving X for %fieldname% %%g
REM saga_cmd 
 REM )

REM REM Trim off the edges of each derivative by a fraction of the original buffer to remove edge artifacts.
REM echo. 
REM for %%a in (%tiles%) do (
REM echo now trimming X for %fieldname% %%a
REM gdalwarp 
REM )

REM REM mosaic files. 
REM setlocal disableDelayedExpansion
REM echo Now mosaicing X
REM set "files="                                                           
 REM for /r . %%g in XXX do call set files=%%files%%;%%g  
  REM saga_cmd 
REM endlocal 

REM REM Convert to .tif format                                              
REM echo Now converting to .tif format
REM saga_cmd 

REM REM Remove intermediate files to reduce disk space 
REM del /S 




 


