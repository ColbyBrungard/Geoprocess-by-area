@echo off
REM ********
rem batch file to calculate multiple terrain derivatives given a DEM and shapefile of HUC watersheds 
rem author Colby W. Brungard PhD
REM Plant and Environmental Sciences Dept.  
REM New Mexico State University 
REM Las Cruces, NM 88003
REM cbrung@nmsu.edu
REM +1-575-646-1907
REM ********* (in case you are wondering; rem = remark)

REM Set needed paths. 
REM I found it easiest to install SAGA directly on the C drive. 
REM modify the following paths to match your saga install
REM path to saga_cmd.exe
set PATH=%PATH%;C:\saga-6.2.0_x64
set SAGA_MLB=C:\saga-6.2.0_x64\tools

REM name of base DEM from which to calculate derivatives
set DEM=C:\DEM\NM_5m_dtm.tif

REM path to HUC8 watershed files. 
REM Both are needed because I clip by the unprojected shapefile and then trim with the projected shapefile. 
REM Use the following to gdal command to reproject shapefile if needed: ogr2ogr -f "ESRI Shapefile" wbdhu10_a_us_september2017_proj.shp wbdhu10_a_us_september2017.shp -t_srs EPSG:10200
REM Oddly enough using two different projections seems to be key to removing border artefacts caused by buffering in. When I use a different projection to clip and reporject the border artifacts go away... Odd, but it works.
set indexA=C:\DEM\wbdhu8_a_us_september2017_USboundCONUS.shp
set indexB=C:\DEM\wbdhu8_a_us_september2017_USboundCONUS_proj.shp

rem The column name of the shapefiles attribute table with the HUC values. Use HUC8 for 10m DEM and HUC6 for 30m DEM
set fieldname=HUC8

rem tiles are the names/values of each polygon. These must be manually input and can be identified as the watersheds that overlay your area of interest. 
set tiles=13020211 13030103 13030101 13030102 13030202 13020210

rem Set a primary and secondary buffer distance in number of pixels. The primary will be used when clipping the DEM by HUC8 watersheds. The secondary will be used to trim off edge effects of each derivative, but leave enough to feather the edges when mosaicking.
set bufferA=100
set bufferB=20


REM start time 
set startTime=%date%:%time%

REM the following script is one that is "embarrassingly parallel", but it runs rather quickly (saga already parallelizes DEM derivative calculations). I decided to include each calculation within it's own for loop. This is very inelegant, but it allows me to calculate a derivative for each watershed, stitch them all together, and then delete the individual derivatives for each watershed to save space (which quickly became an issue for large DEMs).

REM please note that this code does NOT fill the DEMs. I found that filling by watershed resulted in very flat areas in the bottom of valleys.

REM 1. Preprocessing
REM Create subfolders to hold derivatives
for %%i in (%tiles%) do (
 mkdir %%i
 )

REM Clip DEM to HUC watershed boundary. 
REM Note: I tried multi-threaded warping -multi -wo NUM_THREADS=val/ALL_CPUS http://www.gdal.org/gdalwarp.html), but it didn't really seem to speed things up.
REM CHANGE -t_srs if you want a different output projection. CHANGE -tr if you want a different resolution 10 10 means 10m x 10m 
REM it is also critical that you set a nodata values otherwise the covariates will be buffered in (as well as outside of the watershed boundary). 
for %%i in (%tiles%) do (
 echo now subsetting %fieldname% %%i
  gdalwarp -t_srs EPSG:102008 -tr 10 10 -r bilinear -multi -dstnodata -9999 -cutline %indexA% -cwhere "%fieldname% = '%%i'" -crop_to_cutline -cblend %bufferA% -of SAGA %DEM% %%i\%%i.sdat
)
  
REM Smooth DEM to remove data artifacts using circle-shaped smooting filter with radius of 4 cells 
for %%i in (%tiles%) do (
 echo now smoothing %fieldname% %%i
  saga_cmd grid_filter 0 -INPUT=%%i\%%i.sdat -RESULT=%%i\%%i_s.sgrd -METHOD=0 -KERNEL_TYPE=1 -KERNEL_RADIUS=4
)
   
	REM REM Remove intermediate files
	REM for %%i in (%tiles%) do (	   
	 REM del %%i\%%i.prj
	 REM del %%i\%%i.sdat
	 REM del %%i\%%i.sdat.aux.xml
	 REM del %%i\%%i.sgrd
	)   
   
REM 2. Calculate Derivatives
REM each code chunk follows the same format: 
 REM 1. Calculate one or more derivatives
 REM 2. Trim off the edges of each derivative by a fraction of the original buffer to remove cells effected by edge artifacts
 REM 3. Remove intermediate files to save space.

REM REM analytical hillshade ##########	   
for %%i in (%tiles%) do (
 echo now calculating analytical hillshade of %fieldname% %%i 
  saga_cmd ta_lighting 0 -ELEVATION=%%i\%%i_s.sgrd -SHADE=%%i\%%i_hsA.sgrd -METHOD=0 -UNIT=1
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming analytical hillshade of %fieldname% %%i
	 	gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_hsA.sdat %%i\%%i_hs.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_hsA.mgrd
		 del %%i\%%i_hsA.prj
		 del %%i\%%i_hsA.sdat
		 del %%i\%%i_hsA.sdat.aux.xml
		 del %%i\%%i_hsA.sgrd
		)

		
REM Profile, plan, longitudinal, cross-sectional, minimum, maximum, and total curvature ##########
for %%i in (%tiles%) do (
 echo now calculating Profile, plan, longitudinal, cross-sectional, minimum, maximum, and total curvature of %fieldname% %%i 
  saga_cmd ta_morphometry 0 -ELEVATION=%%i\%%i_s.sgrd -C_PROF=%%i\%%i_profcA.sgrd -C_PLAN=%%i\%%i_plancA.sgrd -C_LONG=%%i\%%i_lcA.sgrd -C_CROS=%%i\%%i_ccA.sgrd -C_MINI=%%i\%%i_mcA.sgrd  -C_MAXI=%%i\%%i_mxcA.sgrd -C_TOTA=%%i\%%i_tcA.sgrd -METHOD=6 -UNIT_SLOPE=2
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Profile Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_profcA.sdat %%i\%%i_profc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_profcA.mgrd
		 del %%i\%%i_profcA.prj
		 del %%i\%%i_profcA.sdat
		 del %%i\%%i_profcA.sdat.aux.xml
		 del %%i\%%i_profcA.sgrd
		)

	for %%i in (%tiles%) do (
	 echo now trimming Plan Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_plancA.sdat %%i\%%i_planc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_plancA.mgrd
		 del %%i\%%i_plancA.prj
		 del %%i\%%i_plancA.sdat
		 del %%i\%%i_plancA.sdat.aux.xml
		 del %%i\%%i_plancA.sgrd
		)	
			
	for %%i in (%tiles%) do (
	 echo now trimming Longitudinal Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_lcA.sdat %%i\%%i_lc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_lcA.mgrd
		 del %%i\%%i_lcA.prj
		 del %%i\%%i_lcA.sdat
		 del %%i\%%i_lcA.sdat.aux.xml
		 del %%i\%%i_lcA.sgrd
		)		
		
	for %%i in (%tiles%) do (
	 echo now trimming Cross Sectional Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_ccA.sdat %%i\%%i_cc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_ccA.mgrd
		 del %%i\%%i_ccA.prj
		 del %%i\%%i_ccA.sdat
		 del %%i\%%i_ccA.sdat.aux.xml
		 del %%i\%%i_ccA.sgrd
		)
		
	for %%i in (%tiles%) do (
	 echo now Minimum Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_mcA.sdat %%i\%%i_mc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_mcA.mgrd
		 del %%i\%%i_mcA.prj
		 del %%i\%%i_mcA.sdat
		 del %%i\%%i_mcA.sdat.aux.xml
		 del %%i\%%i_mcA.sgrd
		)
		
	for %%i in (%tiles%) do (
	 echo now trimming Maximum Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_mxcA.sdat %%i\%%i_mxc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_mxcA.mgrd
		 del %%i\%%i_mxcA.prj
		 del %%i\%%i_mxcA.sdat
		 del %%i\%%i_mxcA.sdat.aux.xml
		 del %%i\%%i_mxcA.sgrd
		)		
		
	for %%i in (%tiles%) do (
	 echo now trimming Total Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_tcA.sdat %%i\%%i_tc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_tcA.mgrd
		 del %%i\%%i_tcA.prj
		 del %%i\%%i_tcA.sdat
		 del %%i\%%i_tcA.sdat.aux.xml
		 del %%i\%%i_tcA.sgrd
		)
		

REM Convergence Index ##########
for %%i in (%tiles%) do (
 echo now calculating Convergence Index of %fieldname% %%i 
  saga_cmd ta_morphometry 1 -ELEVATION=%%i\%%i_s.sgrd -RESULT=%%i\%%i_ciA.sgrd -METHOD=1 -NEIGHBOURS=1
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Convergence Index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_ciA.sdat %%i\%%i_ci.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_ciA.mgrd
		 del %%i\%%i_ciA.prj
		 del %%i\%%i_ciA.sdat
		 del %%i\%%i_ciA.sdat.aux.xml
		 del %%i\%%i_ciA.sgrd
		)
		
		
REM Diurnal Anisotropic Heating ##########
for %%i in (%tiles%) do (
 echo now calculating Diurnal Anisotropic Heating of %fieldname% %%i 
  saga_cmd ta_morphometry 12 -DEM=%%i\%%i_s.sgrd -DAH=%%i\%%i_dahA.sgrd -ALPHA_MAX=225
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Diurnal Anisotropic Heating of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_dahA.sdat %%i\%%i_dah.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_dahA.mgrd
		 del %%i\%%i_dahA.prj
		 del %%i\%%i_dahA.sdat
		 del %%i\%%i_dahA.sdat.aux.xml
		 del %%i\%%i_dahA.sgrd
		)
		

REM MultiScale Topographic Position Index ##########
for %%i in (%tiles%) do (
 echo now calculating MultiScale Topographic Position Index of %fieldname% %%i 
  saga_cmd ta_morphometry 28 -DEM=%%i\%%i_s.sgrd -TPI=%%i\%%i_tpiA.sgrd -SCALE_MIN=1 -SCALE_MAX=8 -SCALE_NUM=3
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming MultiScale Topographic Position Index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_tpiA.sdat %%i\%%i_tpi.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_tpiA.mgrd
		 del %%i\%%i_tpiA.prj
		 del %%i\%%i_tpiA.sdat
		 del %%i\%%i_tpiA.sdat.aux.xml
		 del %%i\%%i_tpiA.sgrd
		)
		

REM MRVBF and MRRTF ##########
for %%i in (%tiles%) do (
 echo now calculating MRVBF and MRRTF of %fieldname% %%i 
  saga_cmd ta_morphometry 8 -DEM=%%i\%%i_s.sgrd -MRVBF=%%i\%%i_mrvbfA.sgrd -MRRTF=%%i\%%i_mrrtfA.sgrd -T_SLOPE=32 
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming MRVBF of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_mrvbfA.sdat %%i\%%i_mrvbf.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_mrvbfA.mgrd
		 del %%i\%%i_mrvbfA.prj
		 del %%i\%%i_mrvbfA.sdat
		 del %%i\%%i_mrvbfA.sdat.aux.xml
		 del %%i\%%i_mrvbfA.sgrd
		)

	for %%i in (%tiles%) do (
	 echo now trimming MRRTF of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_mrrtfA.sdat %%i\%%i_mrrtf.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_mrrtfA.mgrd
		 del %%i\%%i_mrrtfA.prj
		 del %%i\%%i_mrrtfA.sdat
		 del %%i\%%i_mrrtfA.sdat.aux.xml
		 del %%i\%%i_mrrtfA.sgrd
		)


REM Terrain Ruggedness Index ##########
for %%i in (%tiles%) do (
 echo now calculating Terrain Ruggedness Index of %fieldname% %%i 
  saga_cmd ta_morphometry 16 -DEM=%%i\%%i_s.sgrd -TRI=%%i\%%i_triA.sgrd -MODE=1 -RADIUS=10
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Terrain Ruggedness Index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_triA.sdat %%i\%%i_tri.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_triA.mgrd
		 del %%i\%%i_triA.prj
		 del %%i\%%i_triA.sdat
		 del %%i\%%i_triA.sdat.aux.xml
		 del %%i\%%i_triA.sgrd
		)
		

REM Terrain Surface Convexity ##########
for %%i in (%tiles%) do (
 echo now calculating Terrain Surface Convexity of %fieldname% %%i 
  saga_cmd ta_morphometry 21 -DEM=%%i\%%i_s.sgrd -CONVEXITY=%%i\%%i_tscA.sgrd -KERNEL=1 -TYPE=0 -EPSILON=0.0 -SCALE=10 -METHOD=1 -DW_WEIGHTING=3 -DW_BANDWIDTH=0.7
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Terrain Surface Convexity of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_tscA.sdat %%i\%%i_tsc.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_tscA.mgrd
		 del %%i\%%i_tscA.prj
		 del %%i\%%i_tscA.sdat
		 del %%i\%%i_tscA.sdat.aux.xml
		 del %%i\%%i_tscA.sgrd
		)
	
		
REM Saga wetness index, catchment area, modified catchment area, and catchment slope ##########
for %%i in (%tiles%) do (
 echo now calculating Saga wetness index catchment area, modificed catchment area, and catchment slope of %fieldname% %%i 
  saga_cmd ta_hydrology 15 -DEM=%%i\%%i_s.sgrd -TWI=%%i\%%i_swiA.sgrd -AREA=%%i\%%i_caA.sgrd -AREA_MOD=%%i\%%i_mcaA.sgrd -SLOPE=%%i\%%i_csA.sgrd
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Saga wetness index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_swiA.sdat %%i\%%i_swi.tif
	)   
	
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_swiA.mgrd
		 del %%i\%%i_swiA.prj
		 del %%i\%%i_swiA.sdat
		 del %%i\%%i_swiA.sdat.aux.xml
		 del %%i\%%i_swiA.sgrd
		)
		
		
	for %%i in (%tiles%) do (
	 echo now trimming Catchment Slope of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_csA.sdat %%i\%%i_cs.tif
	)
	
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_csA.mgrd
		 del %%i\%%i_csA.prj
		 del %%i\%%i_csA.sdat
		 del %%i\%%i_csA.sdat.aux.xml
		 del %%i\%%i_csA.sgrd
		)
	
	for %%i in (%tiles%) do (
	 echo now trimming Modified Catchment Area of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_mcaA.sdat %%i\%%i_mca.tif
	)
	 
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_mcaA.mgrd
		 del %%i\%%i_mcaA.prj
		 del %%i\%%i_mcaA.sdat
		 del %%i\%%i_mcaA.sdat.aux.xml
		 del %%i\%%i_mcaA.sgrd
		)		


REM Slope ##########			
for %%i in (%tiles%) do (
 echo now calculating Slope of %fieldname% %%i 
  saga_cmd ta_morphometry 0 -ELEVATION=%%i\%%i_s.sgrd -SLOPE=%%i\%%i_slA.sgrd -METHOD=2 -UNIT_SLOPE=2
   )

   
REM Stream power index - requires slope and catchment area as input ##########
for %%i in (%tiles%) do (
 echo now calculating stream power index of %fieldname% %%i
  saga_cmd ta_hydrology 21 -SLOPE=%%i\%%i_slA.sgrd -AREA=%%i\%%i_caA.sgrd -SPI=%%i\%%i_spiA.sgrd
  )

    for %%i in (%tiles%) do (
	 echo now trimming stream power index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_spiA.sdat %%i\%%i_spi.tif
	) 
	
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_spiA.mgrd
		 del %%i\%%i_spiA.prj
		 del %%i\%%i_spiA.sdat
		 del %%i\%%i_spiA.sdat.aux.xml
		 del %%i\%%i_spiA.sgrd
		)
		
			
REM Topographic wetness index - requires slope and catchment area as input ##########
for %%i in (%tiles%) do (
 echo now calculating topographic wetness index of %fieldname% %%i
  saga_cmd ta_hydrology 20 -SLOPE=%%i\%%i_slA.sgrd -AREA=%%i\%%i_caA.sgrd -TWI=%%i\%%i_twiA.sgrd
  )

    for %%i in (%tiles%) do (
	 echo now trimming topographic wetness index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_twiA.sdat %%i\%%i_twi.tif
	) 	
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_twiA.mgrd
		 del %%i\%%i_twiA.prj
		 del %%i\%%i_twiA.sdat
		 del %%i\%%i_twiA.sdat.aux.xml
		 del %%i\%%i_twiA.sgrd
		)
	
	
REM Trim Slope and catchment area, delete intermediate files (this is not done before because SPI and TWI need slope and catchment area as input
for %%i in (%tiles%) do (
 echo now trimming Slope of %fieldname% %%i
  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_slA.sdat %%i\%%i_sl.tif
) 

for %%i in (%tiles%) do (
 echo now trimming Catchment Area index of %fieldname% %%i
  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_caA.sdat %%i\%%i_ca.tif
)	

 for %%i in (%tiles%) do (	   
  del %%i\%%i_slA.mgrd
  del %%i\%%i_slA.prj
  del %%i\%%i_slA.sdat
  del %%i\%%i_slA.sdat.aux.xml
  del %%i\%%i_slA.sgrd
 ) 
 
 for %%i in (%tiles%) do (	   
  del %%i\%%i_caA.mgrd
  del %%i\%%i_caA.prj
  del %%i\%%i_caA.sdat
  del %%i\%%i_caA.sdat.aux.xml
  del %%i\%%i_caA.sgrd
 )
 

		
REM Positive Topographic Openness ##########
for %%i in (%tiles%) do (
 echo now calculating Positive Topographic Openness of %fieldname% %%i 
  saga_cmd ta_lighting 5 -DEM=%%i\%%i_s.sdat -POS=%%i\%%i_poA.sgrd -RADIUS=%bufferA% -METHOD=1 -DLEVEL=3.0 -NDIRS=8
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Positive Topographic Openness of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_poA.sdat %%i\%%i_po.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_poA.mgrd
		 del %%i\%%i_poA.prj
		 del %%i\%%i_poA.sdat
		 del %%i\%%i_poA.sdat.aux.xml
		 del %%i\%%i_poA.sgrd
		)

REM Mass Balance Index ##########
for %%i in (%tiles%) do (
 echo now calculating Mass Balance Index of %fieldname% %%i 
  saga_cmd ta_morphometry 10 -DEM=%%i\%%i_s.sdat -MBI=%%i\%%i_mbiA.sgrd -TSLOPE=15.000000 -TCURVE=0.010000 -THREL=15.000000
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Mass Balance Index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -multi -dstnodata -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_mbiA.sdat %%i\%%i_mbi.tif
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_mbiA.mgrd
		 del %%i\%%i_mbiA.prj
		 del %%i\%%i_mbiA.sdat
		 del %%i\%%i_mbiA.sdat.aux.xml
		 del %%i\%%i_mbiA.sgrd
		)		

REM Trim the smoothed DEM ##########
for %%i in (%tiles%) do (
 echo now trimming elevation of %fieldname% %%i
  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -dstnodata -multi -9999 -tr 10 10 -co COMPRESS=DEFLATE %%i\%%i_s.sdat %%i\%%i_s.tif
	)   

	for %%i in (%tiles%) do (	   
	 del %%i\%%i_s.mgrd
	 del %%i\%%i_s.prj
	 del %%i\%%i_s.sdat
	 del %%i\%%i_s.sdat.aux.xml
	 del %%i\%%i_s.sgrd
	)

		
echo Start Time: %startTime%
echo Finish Time: %date%:%time%


REM REM THIS IS THE BASE CODE BLOCK
REM REM X ##########
REM REM for %%i in (%tiles%) do (
 REM REM echo now calculating X of %fieldname% %%i 
  REM REM saga_cmd X
   REM REM )
   
	REM REM for %%i in (%tiles%) do (
	 REM REM echo now X of %fieldname% %%i
	  REM REM gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -multi -crop_to_cutline -dstnodata -9999 -co COMPRESS=DEFLATE %%i_X.sdat %%i_X.tif
	REM REM )   
	   
		REM REM for %%i in (%tiles%) do (	   
		 REM REM del %%i_X.mgrd
		 REM REM del %%i_X.prj
		 REM REM del %%i_X.sdat
		 REM REM del %%i_X.sdat.aux.xml
		 REM REM del %%i_X.sgrd
		REM REM )
		
	
