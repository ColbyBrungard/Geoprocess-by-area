@echo off
REM ********
rem batch file to calculate multiple terrain derivatives given a DEM and base 
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
set SAGA_MLB=C:\saga-6.2.0_x64\tools

REM name of DEM to calculate derivatives from
set DEM=C:\DEM\NM_5m_dtm.tif

REM path to HUC8 watershed files. Both are needed because I clip by the unprojected shapefile and then trim with the projected shapefile. 
REM Use the following to reproject shapefile if needed: ogr2ogr -f "ESRI Shapefile" wbdhu10_a_us_september2017_proj.shp wbdhu10_a_us_september2017.shp -t_srs EPSG:102008
set indexA=C:\DEM\wbdhu8_a_us_september2017.shp
set indexB=C:\DEM\wbdhu8_a_us_september2017_proj.shp

rem The column name of the shapefiles attribute table with the HUC8 values. 
set fieldname=HUC8

rem tiles are the names/values of each polygon. These must be manually input. 13020210 13020211 13030101 13030102 13030202
set tiles=13030103 13020210 13020211 13030101 13030102 13030202

rem Set a primary and secondary buffer distance in number of pixels. The primary will be used when clipping the DEM by HUC8 watersheds. The secondary will be used to trim off edge effects of each derivative, but leave enough to feather the edges when mosaicking.
set bufferA=100
set bufferB=20


REM start time 
set startTime=%time%

REM the following script is one that is "embarrassingly parallel", but it runs rather quickly (saga already parallelizes DEM derivative calculations), and I thought it too difficult to try and parallelize it in a batch command. 

REM I decided to include each calculation within it's own for loop. This is very inelegant, but it allows me to calculate a derivative for each watershed, stitch them all together, and then delete the individual derivatives for each watershed to save space (which quickly became an issue for large DEMs).

REM 1. Preprocessing
REM Create subfolders to hold derivatives
for %%i in (%tiles%) do (
 mkdir %%i
 )

REM Clip DEM to HUC8 watershed boundary. Note: I tried multi-threaded warping -multi -wo NUM_THREADS=val/ALL_CPUS http://www.gdal.org/gdalwarp.html), but it didn't really seem to speed things up. 
for %%i in (%tiles%) do (
 echo now subsetting %fieldname% %%i
  gdalwarp -t_srs EPSG:102008 -tr 10 10 -r bilinear -dstnodata -9999 -cutline %indexA% -cwhere "%fieldname% = '%%i'" -crop_to_cutline -cblend %bufferA% -of SAGA %DEM% %%i\%%i.sdat
)
  
REM Smooth DEM to remove data artifacts using circle with radius of 4 cells) smoothing filter 
for %%i in (%tiles%) do (
 echo now smoothing %fieldname% %%i
  saga_cmd grid_filter 0 -INPUT=%%i\%%i.sdat -RESULT=%%i\%%i_s.sgrd -METHOD=0 -KERNEL_TYPE=1 -KERNEL_RADIUS=4
)
   

REM Remove intermediate files
for %%i in (%tiles%) do (	   
 del %%i\%%i.prj
 del %%i\%%i.sdat
 del %%i\%%i.sdat.aux.xml
 del %%i\%%i.sgrd
 )   
   
REM 2. Calculate Derivatives
REM each code chunk follows the same format: 
 REM 1. Calculate one or more derivatives
 REM 2. Trim off the edges of each derivative by a fraction of the original buffer to remove cells effected by edge artifacts
 REM 3. Remove intermediate files to save space.

REM analytical hillshade ##########	   
for %%i in (%tiles%) do (
 echo now calculating analytical hillshade of %fieldname% %%i 
  saga_cmd ta_lighting 0 -ELEVATION=%%i\%%i_s.sgrd -SHADE=%%i\%%i_hsA.sgrd -METHOD=0 -UNIT=1
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming analytical hillshade of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_hsA.sdat %%i\%%i_hs.sdat
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_hsA.mgrd
		 del %%i\%%i_hsA.prj
		 del %%i\%%i_hsA.sdat
		 del %%i\%%i_hsA.sdat.aux.xml
		 del %%i\%%i_hsA.sgrd
		)

		
REM Flow Line Curvature ##########
for %%i in (%tiles%) do (
 echo now calculating Flow Line Curvature of %fieldname% %%i 
  saga_cmd ta_morphometry 0 -ELEVATION=%%i\%%i_sf.sgrd -C_ROTO=%%i\%%i_fcA.sgrd -METHOD=2 -UNIT_SLOPE=2
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Flow Line Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_fcA.sdat %%i\%%i_fc.sdat
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_fcA.mgrd
		 del %%i\%%i_fcA.prj
		 del %%i\%%i_fcA.sdat
		 del %%i\%%i_fcA.sdat.aux.xml
		 del %%i\%%i_fcA.sgrd
		)
		
		
REM Profile, plan, longitudinal, cross-sectional, minimum, maximum, and total curvature ##########
for %%i in (%tiles%) do (
 echo now calculating Profile, plan, longitudinal, cross-sectional, minimum, maximum, and total curvature of %fieldname% %%i 
  saga_cmd ta_morphometry 0 -ELEVATION=%%i\%%i_sf.sgrd -C_PROF=%%i\%%i_profcA.sgrd -C_PLAN=%%i\%%i_plancA.sgrd -C_LONG=%%i\%%i_lcA.sgrd -C_CROS=%%i\%%i_ccA.sgrd -C_MINI=%%i\%%i_mcA.sgrd  -C_MAXI=%%i\%%i_mxcA.sgrd -C_TOTA=%%i\%%i_tcA.sgrd -METHOD=6 -UNIT_SLOPE=2
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Profile Curvature of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_profcA.sdat %%i\%%i_profc.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_plancA.sdat %%i\%%i_planc.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_lcA.sdat %%i\%%i_lc.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_ccA.sdat %%i\%%i_cc.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_mcA.sdat %%i\%%i_mc.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_mxcA.sdat %%i\%%i_mxc.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_tcA.sdat %%i\%%i_tc.sdat
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
  saga_cmd ta_morphometry 1 -ELEVATION=%%i\%%i_sf.sgrd -RESULT=%%i\%%i_ciA.sgrd -METHOD=1 -NEIGHBOURS=1
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Convergence Index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_ciA.sdat %%i\%%i_ci.sdat
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
  saga_cmd ta_morphometry 12 -DEM=%%i\%%i_sf.sgrd -DAH=%%i\%%i_dahA.sgrd -ALPHA_MAX=225
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Diurnal Anisotropic Heating of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_dahA.sdat %%i\%%i_dah.sdat
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
  saga_cmd ta_morphometry 28 -DEM=%%i\%%i_sf.sgrd -TPI=%%i\%%i_tpiA.sgrd -SCALE_MIN=1 -SCALE_MAX=8 -SCALE_NUM=3
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming MultiScale Topographic Position Index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_tpiA.sdat %%i\%%i_tpi.sdat
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
  saga_cmd ta_morphometry 8 -DEM=%%i\%%i_sf.sgrd -MRVBF=%%i\%%i_mrvbfA.sgrd -MRRTF=%%i\%%i_mrrtfA.sgrd -T_SLOPE=32 
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming MRVBF of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_mrvbfA.sdat %%i\%%i_mrvbf.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_mrrtfA.sdat %%i\%%i_mrrtf.sdat
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
  saga_cmd ta_morphometry 16 -DEM=%%i\%%i_sf.sgrd -TRI=%%i\%%i_triA.sgrd -MODE=1 -RADIUS=10
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Terrain Ruggedness Index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_triA.sdat %%i\%%i_tri.sdat
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
  saga_cmd ta_morphometry 21 -DEM=%%i\%%i_sf.sgrd -CONVEXITY=%%i\%%i_tscA.sgrd -KERNEL=1 -TYPE=0 -EPSILON=0.0 -SCALE=10 -METHOD=1 -DW_WEIGHTING=3 -DW_BANDWIDTH=0.7
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Terrain Surface Convexity of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_tscA.sdat %%i\%%i_tsc.sdat
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_tscA.mgrd
		 del %%i\%%i_tscA.prj
		 del %%i\%%i_tscA.sdat
		 del %%i\%%i_tscA.sdat.aux.xml
		 del %%i\%%i_tscA.sgrd
		)
	
		
REM Saga wetness index, catchment area, modificed catchment area, and catchment slope ##########
for %%i in (%tiles%) do (
 echo now calculating Saga wetness index catchment area, modificed catchment area, and catchment slope of %fieldname% %%i 
  saga_cmd ta_hydrology 15 -DEM=%%i\%%i_sf.sgrd -TWI=%%i\%%i_swiA.sgrd -AREA=%%i\%%i_caA.sgrd -AREA_MOD=%%i\%%i_mcaA.sgrd -SLOPE=%%i\%%i_csA.sgrd
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Saga wetness index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_swiA.sdat %%i\%%i_swi.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_csA.sdat %%i\%%i_cs.sdat
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
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_mcaA.sdat %%i\%%i_mca.sdat
	)
	 
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_mcaA.mgrd
		 del %%i\%%i_mcaA.prj
		 del %%i\%%i_mcaA.sdat
		 del %%i\%%i_mcaA.sdat.aux.xml
		 del %%i\%%i_mcaA.sgrd
		)		


REM Slope 			
for %%i in (%tiles%) do (
 echo now calculating Slope of %fieldname% %%i 
  saga_cmd ta_morphometry 0 -ELEVATION=%%i\%%i_sf.sgrd -SLOPE=%%i\%%i_slA.sgrd -METHOD=2 -UNIT_SLOPE=2
   )

   
REM Stream power index - requires slope and catchment area as input
for %%i in (%tiles%) do (
 echo now calculating stream power index of %fieldname% %%i
  saga_cmd ta_hydrology 21 -SLOPE=%%i\%%i_slA.sgrd -AREA=%%i\%%i_caA.sgrd -SPI=%%i\%%i_spiA.sgrd
  )

    for %%i in (%tiles%) do (
	 echo now trimming stream power index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_spiA.sdat %%i\%%i_spi.sdat
	) 
	
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_spiA.mgrd
		 del %%i\%%i_spiA.prj
		 del %%i\%%i_spiA.sdat
		 del %%i\%%i_spiA.sdat.aux.xml
		 del %%i\%%i_spiA.sgrd
		)
		
			
REM Topographic wetness index - requires slope and catchment area as input
for %%i in (%tiles%) do (
 echo now calculating topographic wetness index of %fieldname% %%i
  saga_cmd ta_hydrology 20 -SLOPE=%%i\%%i_sAl.sgrd -AREA=%%i\%%i_caA.sgrd -TWI=%%i\%%i_twiA.sgrd
  )

    for %%i in (%tiles%) do (
	 echo now trimming topographic wetness index of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_twiA.sdat %%i\%%i_twi.sdat
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
  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_slA.sdat %%i\%%i_sl.sdat
) 

for %%i in (%tiles%) do (
 echo now trimming Catchment Area index of %fieldname% %%i
  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_caA.sdat %%i\%%i_ca.sdat
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
 

		
REM Positive Topographic Openness
for %%i in (%tiles%) do (
 echo now calculating Positive Topographic Openness of %fieldname% %%i 
  saga_cmd ta_lighting 5 -DEM=%%i\%%i_sf.sdat -POS=%%i\%%i_poA.sgrd -RADIUS=%bufferA% -METHOD=1 -DLEVEL=3.0 -NDIRS=8
   )
   
	for %%i in (%tiles%) do (
	 echo now trimming Positive Topographic Openness of %fieldname% %%i
	  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_poA.sdat %%i\%%i_po.sdat
	)   
	   
		for %%i in (%tiles%) do (	   
		 del %%i\%%i_poA.mgrd
		 del %%i\%%i_poA.prj
		 del %%i\%%i_poA.sdat
		 del %%i\%%i_poA.sdat.aux.xml
		 del %%i\%%i_poA.sgrd
		)


REM Trim the smoothed DEM and rename
for %%i in (%tiles%) do (
 echo now trimming elevation of %fieldname% %%i
  gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i\%%i_sf.sdat %%i\%%i_el.sdat
	)   

	for %%i in (%tiles%) do (	   
	 del %%i\%%i_sf.mgrd
	 del %%i\%%i_sf.prj
	 del %%i\%%i_sf.sdat
	 del %%i\%%i_sf.sdat.aux.xml
	 del %%i\%%i_sf.sgrd
	)

		
echo Start Time: %startTime%
echo Finish Time: %time%

REM Took about 32 hours... but hung up because I didn't restart it so I'm guessing actual run time is < 24 hours. 


REM REM THIS IS THE BASE CODE BLOCK
REM REM X ##########
REM REM for %%i in (%tiles%) do (
 REM REM echo now calculating X of %fieldname% %%i 
  REM REM saga_cmd X
   REM REM )
   
	REM REM for %%i in (%tiles%) do (
	 REM REM echo now X of %fieldname% %%i
	  REM REM gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %bufferB% -crop_to_cutline -of SAGA %%i_X.sdat %%i_X.sdat
	REM REM )   
	   
		REM REM for %%i in (%tiles%) do (	   
		 REM REM del %%i_X.mgrd
		 REM REM del %%i_X.prj
		 REM REM del %%i_X.sdat
		 REM REM del %%i_X.sdat.aux.xml
		 REM REM del %%i_X.sgrd
		REM REM )
		
	
