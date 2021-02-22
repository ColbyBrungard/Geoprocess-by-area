@echo off
REM ********
rem batch file to calculate multiple terrain derivatives for one input DEM 
rem author Colby W. Brungard PhD
REM Plant and Environmental Sciences Dept.  
REM New Mexico State University 
REM Las Cruces, NM 88003
REM cbrung@nmsu.edu
REM +1-575-646-1907
REM ********* (in case you are wondering; rem = remark)

REM change the output buffer so it is possible to see all of the output on the cmd window
mode con lines=32766


REM start time 
set startTime=%date%:%time%


REM Set needed paths. 
REM I found it easiest to install SAGA directly on the C drive. 
REM modify the following paths to match your saga install
REM path to saga_cmd.exe
REM I have tried this with saga versions 6.2.0, 7.4.0, and 7.6.3; I strongly suspect that this will work with other newer versions however. 
SET SAGA_TLB=C:\saga-7.4.0_x64
SET PATH=%PATH%;C:\saga-7.4.0_x64

REM To convert to saga grid format
REM Explicitly setting the nodata value is surprisingly important when converting to saga grid format. Saga's default nodata value is -99999, but if this is not explicitly set the nodata values are set to 0. Not explicitly setting a nodata value has the most effect on multiscale geomorphons, baselevel (and thus vertical distance to channel network), ridge height (and thus valley depth), and mrvbf/mrrtf.
gdalwarp -t_srs EPSG:5070 -tr 30 30 -r bilinear -dstnodata -99999 -of SAGA C:\geoproc_test\Town_of_Madrid_Saint_Johns_Bayoufel.tif C:\geoproc_test\Town_of_Madrid_Saint_Johns_Bayoufel.sdat


REM Set common inputs 
REM the input DEM in saga format. 
set basedem=C:\geoproc_test\Town_of_Madrid_Saint_Johns_Bayoufel.sdat
REM The \ after the folder path is very important to ensure that files go where I think they should.
set desFol=C:\geoproc_test\
REM neighboorhood sizes overwhich to calculate derivatives. 128 took a long time and for a 30m DEM would be 3.8 km, which I'm thinking is too large for the additional processing time required. This is used for many covariates so it makes sense to set it here. I also decided not to use a 64 neighborhood because dropping it cut processing time almost in half! 
set neighbors=2 4 8 16 32
REM valley depth and vertical distance to channel network need a strahler order, set these here. Unfortunatley the base-level interpolation has some issues which are most egregious at a strahler order = 1, so I only use >=2. I also do not use strahler orders > 6 because a few tests seem to indicate that strahler order of 7 was probably too high a value for HUC6 watersheds. It would probably be appropriate at a HUC4 watershed scale.  
set orders=2 3 4 5 6
REM valley depth and vertical distance to channel network produce a few spurious negative cells. The tool that changes these values needs a look-up-table. Set that here.
set LUT=C:\geoproc_test\.lut_reclass.txt


REM REM ############## Start Computation



REM analytical hillshade ##########	   
REM Input: DEM
REM Parameters:
 REM -METHOD
 REM -POSITION: The suns position. 0 = azimuth and height, 1 = date and time. 
 REM -AZIMUTH (if position = 0): Direction from north. 255 = southwest
 REM -DECLINATION (if position = 0): Angle above horizon. 45 makes a nice hillshade.
 REM -DATE (if position = 1): The day of the year to make the calculation.
 REM -TIME (if position = 1): The number of hours to calculate for. 
 REM -EXAGGERATION: allows increased contrasts in flat areas. Left as one. 
 REM -UNIT: 0 = radians, 1 = degrees. Degrees seemed more interpretable to me. 
REM Output: Low values = high likely incedent radiation (few shadows), high values =  low indident radiation (many shadows). 
REM Notes: 
 REM The -METHOD and -POSITION parameters are most influential on this calculation. 
 REM The -METHOD parameter has five options. I found that the "standard" and "limited max" arguments produced the same results (r2 = 100). "With shadows" only crashed saga (and is just a mask anyway). "Ambient occlusion" took a long time to run and produced artifacts, it also had several different parameters making this more difficult and not a good option. "Combined shading" multiplies the standard method by the normalized slope. I chose both "standard" and "combined shading" with -POSITION = 0 to produce hillshades for visual effects because I thought that these were most useful for vizulizing the landscape. These two terrain derivatives are intended for visulization and not necessarily analysis. 

REM Visual hillshades
saga_cmd ta_lighting 0 -ELEVATION=%basedem% -SHADE=%desFol%hs_st.sgrd -METHOD=0 -POSITION=0 -AZIMUTH=255.000000 -DECLINATION=45.000000 -EXAGGERATION=1.000000 -UNIT=1
saga_cmd ta_lighting 0 -ELEVATION=%basedem% -SHADE=%desFol%hs_cs.sgrd -METHOD=5 -POSITION=0 -AZIMUTH=255.000000 -DECLINATION=45.000000 -EXAGGERATION=1.000000 -UNIT=1
echo %date%:%time%



REM Tool: Potential Incoming Solar Radiation ##########
REM The amount of potential annual insolation that could be receieved at each grid cell for a particular day.  
REM input: Elevation, (optional input is sky view factor, but see -LOCALSVF parameter).
REM Parameters:
 REM -SOLARCONST; Solar constant (W/m2). Used the default value
 REM -LOCALSVF; 0 = do not use local skyview factor, 1 = use skyview factor based on local slope 
 REM -UNITS; units of output. 0 = kWh/m2, 1 = kJ/m2, 2 = J/cm2
 REM -SHADOW; How are shadows calculated. 0 = grid node shadow, 1=whole cells shadow, 2 = none. Used 1 because it should show less artifacts
 REM -LOCATION; latitude. 0=constant latitude, 1=calculate from grid system. I do not know if this is the grid system (e.g., projection) or the actual grid. I'm hoping it is the latter. 
 REM -PERIOD. What time period is the calculation for? 0=moment, 1=day, 2=range of days
 REM -DAY=2021-01-29. If -PERIOD=1 (day) what day to calculate? I chose to calculate this for the 22nd of each month because this captured, very closely, both equinoxes and soltices. 
 REM -HOUR_RANGE_MIN; start of time spance used for calculation of daily radiation sums
 REM -HOUR_RANGE_MAX; end of time spance used for calculation of daily radiation sums (seting these to 0 to 24 seemed appropriate. I tested 0;24 against 0;12 and it had an R2 of >80. 0;24 vs 4;20 (which makes more sense for the max day length at the northern border of the US (and thus longest day) had a correlatoin of 100. Since this does not have a huge effect on computation time I chose to leave this as min=0 and max=24). Note all correlations are for direction insolation. Nothing really changed for diffuse insolation. 
 REM -HOUR_STEP; time step for a day's calculation in hours. Shortening this results in faster calculations. I tried time steps of 0.5, 1, 2, 4, and 8. The direct insolation correlation between 0.5 vs 1, 1 vs 2, and 2 vs 4 was > 97.5%. The correlation between 4 and 8 was 76.3%, thus I used a value of 4 as this made the calculations faster but produced almost the same results as the 0.5 time step. This parameter had practically no influence on diffuse solar radiation. 
 REM -METHOD; what method to use for atmospheric transmittance. 0=height of atmosphere and vapour pressure (requires height of atmosphere as input), 1=Air pressure, water and dust content (requires barometric pressure, water content, and dust), 2=lumped atmospheric transmittance (requires percent), 3=Hofierka and Suri (requires a turbidity coefficient(default is 3). Methods 2 and 3 require the least inputs and are thus likely the most generalizable. Testing -METHOD= 2 vs 3 (with default parameters, -DAY of Jan 29th and -HOUR_STEP = 4) had a correlation of >98%, thus I concluded that this didn't matter to much so I used the lumped atmospheric transmittance as I think it made the fewest assumptions.  
 REM -LUMPED; the percent of atmospheric transmittance. Left as default. 
REM Notes: The monthly grids for the half of the year following the summer solstice (e.g., solar angle is decreasing) are essentially equivalent (r2 > 98) to those of the first half of the year (solar angle increasing). The grids for the spring/atumnal equinoxs are equal. DSM applications should not use all of these covariates, but instead choose what is relevant for their area application. At a minimum I think the summer and winter solstices, and one of the equinoxes should be included, and possibly ratios of indivudal months. Even though the values are very similar, I decided to calculate these for every month because I could anticipate some applications where they might want spring or autumn values. 
REM Output 
 REM -GRD_DIRECT; direct solar radiation
 REM -GRD_DIFFUS; diffuse solar radiation
 REM -GRD_TOTAL; total solar radiation (did not use as it can be derived from both direct and diffuse)
 REM -GRD_RATIO; direct to difuse ratio (did not use as it can be derived from both direct and diffuse)
 REM -GRD_FLAT; Compare to flat terrain (did not use)
 REM -GRD_DURATION; Duration of insolation (did not use)
 REM -GRD_SUNRISE; time of sunrise (I think (did not use)
 REM -GRD_SUNSET; time of sunset (I think) (did not use)
set days=2021-01-22 2021-02-22 2021-03-22 2021-04-22 2021-05-22 2021-06-22 2021-07-22 2021-08-22 2021-09-22 2021-10-22 2021-11-22 2021-12-22
for %%i in (%days%) do (
echo now calculating potential incoming solar radiation for %%i
saga_cmd ta_lighting 2 -GRD_DEM=%basedem% -GRD_DIRECT=%desFol%pisr_dir_%%i.sdat -GRD_DIFFUS=%desFol%pisr_dif.sdat -SOLARCONST=1367.000000 -LOCALSVF=1 -UNITS=0 -SHADOW=1 -LOCATION=1 -PERIOD=1 -DAY=%%i -HOUR_RANGE_MIN=0.000000 -HOUR_RANGE_MAX=24.000000 -HOUR_STEP=4.000000 -METHOD=2 -LUMPED=70.000000
)
echo %date%:%time%


REM Diurnal Anisotropic Heating ##########
REM input: 
REM parameters:
REM setting alpha_max, direction of sun, 225 = southwest. 
REM notes: results in inversve values if I set alpha_max=45 (northeast). Not much reason to make both soutwestness and northwestness. The other directions don't make much sense.  This is esentially southwestness. 
saga_cmd ta_morphometry 12 -DEM=%basedem% -DAH=%desFol%dah.sgrd -ALPHA_MAX=225	
echo %date%:%time%


REM Positive Topographic Openness ##########
REM Explanation: Openness has been related to how wide a landscape can be viewed from any position
REM input: Elevation
REM parameters:
 REM Radial Limit
 REM method 0 = multi scale, 1 = line tracing
 REM I think that line-tracing (rather than multiscale) makes a bit more sense as I have control over the radial limit.
 REM Multiscale has has a multiscale factor, but I don't understand this
 REM -NDIRS Number of sectors (clockwise from north, how many pie shaped wedges to iterate over). 8 divides the compas into 45 degree angles
 REM -UNIT 0 = radians, 1 = degrees
 REM -NADIR=1 if set, output angels are the mean difference from nadir, or else a plane. I think this makes sense to set it.
REM Output: po = positive openness, no = negative openness
REM Notes: positive and negative openness values are all very different. PO (and NO) rasters with radius values between 2 and 16 have a R2 =100 so it doesn't make sense to calculate for these radius'. The correlations begin to change after a radius of 32, however radius values between 32 and 256 are relativily similar. Thus I chose to use radius of 2, 32, and 128 as these have the lowest correlation (128 and 256 are very simlar, but 128 calculates faster). This should cover the whole spectrum for both positive and negative openess with a minimum computation time. 
set radialLimit=2 32 256
for %%i in (%radialLimit%) do (
echo now calculating positive and negative openness for a size %%i neighborhood
  saga_cmd ta_lighting 5 -DEM=%basedem% -POS=%desFol%po_%%i.sgrd -NEG=%desFol%no_%%i.sgrd -RADIUS=%%i -METHOD=1 -NDIRS=8 -UNIT=1 -NADIR=1
   )
echo %date%:%time%



REM Vertical distance to channel network ##########
REM This tool calculates the vertical distance to a channel network base level (i.e., base level relative elevation). The algorithm consists of two major steps: 1. Interpolation of a channel network base level elevation using splines. 2. Subtraction of this base level from the original elevations. https://sourceforge.net/p/saga-gis/discussion/790705/thread/32283cc3/ https://sourceforge.net/p/saga-gis/discussion/354013/thread/1426f9e5/
REM Input: 
	REM ELEVATION; DEM
	REM CHANNEL NETWORK; The Channel network is a grid that indicates which cells are 'channels' and which is used to make the interpolation. A channel network can be created in a number of ways including from a flow accumulation grid and a threshold to determine when a channel begins, or from the strahler order. Using flow accumulation+threshold gives more control (particularly because it is possible to use a multiple-flow routing algorithm), but this is much more subjective than the strahler approach (which only uses D8) because there are multiple methods to caclulcate flow accumulation and a specific threshold would be much difficult to pick). 
REM First create the CHANNEL NETWORK grid
 REM Input: -DEM; digital elevation model
 REM parameters:
	REM -THRESHOLD; strahler order
 REM Output:
	REM -DIRECTION; flow direction (i.e., aspect). Did not use
	REM -CONNECTION; flow connectivity. Did not use
	REM -ORDER; strahler order channel network grid. 
	REM -BASIN; drainage basins grid. Did not use
	REM -SEGMENTS; stream channels (shapefile). This is the strahler order grid converted to a vector. Did not use
	REM -BASINS; drainage basins (shapefile). This is the drainage basins converted to a shapefile. Did not use
	REM -NODES; stram junctions where strahler order steams connect. Did not use
for %%i in (%orders%) do (
echo now creating Strahler Order %%i stream grid
saga_cmd ta_channels 5 -DEM=%basedem% -ORDER=%desFol%strordr_%%i.sgrd -THRESHOLD=%%i
)
REM Now create Vertical distance to channel network ##########
REM Parameters: See notes for 'valley depth'
	REM -THRESHOLD, maximum change in elevation units (meters), iteration is stopped one maximum change reaches this threshold.
	REM -MAXITER, Maximum number of iterations, ignored if set to 0. May not make a lot of sense unless the threshold is very high. 
	REM -NOUNDERGROUND, should the interpolated elevation be kept above the DEM surface. 1 = yes.    
for %%i in (%orders%) do (
echo now creating vertical distance to elevation grid for strahler order %%i
saga_cmd ta_channels 3 -ELEVATION=%basedem% -CHANNELS=%desFol%strordr_%%i.sgrd -DISTANCE=%desFol%vdcn_%%i.sgrd -BASELEVEL=%desFol%bl_%%i.sgrd -THRESHOLD=100.000000 -MAXITER=0 -NOUNDERGROUND=1
)
echo %date%:%time%

REM Change grid values. 
 REM The vertical distance to channel network grid has a number of negative values because of the way that the base level interpolation is handled. Change these values to 0, which is what they should be.
REM Input: 
	REM vertical distance to channel network (from tool output)
	REM Look up tabl that indicates which values should be reclassified and what they should be changed to. The easiset way to create this is from the SAGA gui for this tool which lets you save the table in the right format. 
REM Output; the input file with the values now reclassified.  
for %%i in (%orders%) do (
saga_cmd grid_tools 12 -INPUT=%desFol%vdcn_%%i.sgrd -OUTPUT=%desFol%vdcn_%%i.sgrd -METHOD=1 -RANGE=LUT
)
echo %date%:%time%

	

REM Tool: Valley Depth.  ##########
REM Explanation: Valley depth is the difference between an interpolated ridge level and the elevation. Valley depth is calculated as difference between the elevation and an interpolated ridge level. Ridge level interpolation uses the algorithm implemented in the 'Vertical Distance to Channel Network' tool. It performs the following steps: 1) Definition of ridge cells (using Strahler order on the inverted DEM), 2) Interpolation of the ridge level, and 3) Subtraction of the original elevations from the ridge level. This is conceptually the inverse of "vertical distance to channel network" but they are not correlated so I think that the calculation is somewhat different. 
REM Inputs: -ELEVATION; digital elevation model
REM Parameters: 
 REM -THRESHOLD, maximum change in elevation units (meters), iteration is stopped one maximum change reaches this threshold.
 REM -MAXITER, Maximum number of iterations, ignored if set to 0. May not make a lot of sense unless the threshold is very high. 
 REM -NOUNDERGROUND, should the interpolated elevation be kept above the DEM surface. 1 = yes.   
 REM -ORDER, called Ridge Detection Threshold in the GUI (min 1, max 7), I believe this is the strahler order (for ridges) to determine when a ridge begins.
REM OUTPUT
 REM -VALLEY_DEPTH (relative depth) units are in meters below the interpolated ridge level
 REM -RIDGE_LEVEL the interpolated ridge level. Units are in meters I think. This is very similar to the base level calculated in the vertical distance to channel network tool for low strahler orders, but begins to change for the higher orders. 
REM Processing notes: 
 REM With default parameters this has a correlation of 97.9% with valley depth derived from  the 'Basic terrain analysis tool'. This tool gives more control however. 
 REM How does this change if I change the tension threshold? Increasing the tension threshold (1, 10, 100) results in different distributions in the lower to middle ranges. Maximum values are larger with larger thresholds.
 REM How does this change if I change the order? Changing the order dramatically influences the results, significantly more than the threshold. This makes sense, because this is finding releative depth over different areas. A high order (e.g. 5) is calculating relative depth using higher order watersheds (e.g., large areas), whereas a lower order (e.g., 1) is finding much more local relative depth. Thus I think that iterating over the orders, but keepting the threshold constant is much more relevant for soil mapping. 
 REM I tested a threshold of 10 and order of 1, vs a threshold of 1000 and an order of 5. The correlations was 94.6%, similar enough to just leave the threshold at 100. I also tested a threshold of 10 and on order of 5 vs a threshold of 1000 and an oder of 5. The correlation was 76.18%, thus the threshold has more of an impact when interpolating across the largest ridges. Still I think that setting the threshold to a middle value of 100 makes the most sense, as the order is more influential. 
for %%i in (%orders%) do (
saga_cmd ta_channels 7 -ELEVATION=%basedem% -VALLEY_DEPTH=%desFol%vd_%%i.sgrd -RIDGE_LEVEL=%desFol%rdgh_%%i.sgrd -THRESHOLD=100.000000 -MAXITER=0 -NOUNDERGROUND=1 -ORDER=%%i
)
echo %date%:%time%
REM Change grid values. 
 REM The valley depth grid has a number of negative values because of the way that the base level interpolation is handled. Change these values to 0, which is what they should be.
REM Input: 
	REM valley depth (from tool output)
	REM Look up tabl that indicates which values should be reclassified and what they should be changed to. The easiset way to create this is from the SAGA gui for this tool which lets you save the table in the right format. 
REM Output; the input file with the values now reclassified.  
for %%i in (%orders%) do (
saga_cmd grid_tools 12 -INPUT=%desFol%vd_%%i.sgrd -OUTPUT=%desFol%vd_%%i.sgrd -METHOD=1 -RANGE=LUT
)
echo %date%:%time%


REM Tool: Geomorphons ##########
REM input: elevation
REM parameters:
REM r.geomorphons in grassGIS has more parameters adjustable by the user 
 REM - THRESHOLD, The relief threshold is a minimum value of the line-of-sight angle (zenith or nadir) that is considered significantly different from the horizon" (Stepinski and Jasiewicz 2011). This parameter has a large influence on the size of the 'flat' areas. A larger threshold value will result in larger areas of the 'flat' class at the expense of the 'slope' classes. I think that setting this to a value to 1 (one degree) makes the most sense and is the most reproducable. I checked this by comparing geomorphons with threhods of 1, 2, and 4 against airphotos. I thought that 2 and 4 over predicted the 'flat' area, although flat vs slope may not be a huge distinction for soil distribution. I would increase this parameter (rather than the search radius) if you feel that the 'flat' class is too small in extent. 
 REM A threshold of 1 means that for a 30m cell size, the difference in grid cell elevations would have to be 0.5 m before the difference was recognozed. 1 degree slope = arctan(rise/run). To figure out the 'rise' in this equation we can replace rise with X and the run with 30 m. Thus the equation becomes 1 = arctan(x/30). Solving for x results in: 30*tangent(1) = x (or 0.5 m). Using the same equation, a 1 degree threshold with a 10m DEM would result in a 0.17 m change before the elevation difference was recognized. This makes it a bit easier to interpret which threshold value should be chosen if you know something about the landscape. I would suspect, that small changes in elevation are very important for some landscapes (e.g., Gilgai), but these would not be detectable with a 30 (or even a 10m) DEM. However; if you are working in a very flat landscape, Geomorphons might not be the best tool anyway.  
 REM -RADIUS, Search radius (in map units I believe, not in number of cells). "The search radius is the maximum allowable distance for calculation of zenith and nadir angles". The radius makes sense to calculate these for the same steps as travis' relative elevation, however in inital tests on one HUC12 watershed the results with L of 1 to 16 were equivalent. However; this parameter has no effect on the results if -METHOD = 0 since this method uses a different parameter (see below). Radius values of 90 and 128 has very similar values. To keep this consistent 
  REM I chose to use radius values of 30, 300, and 3000. There is not much difference between 300 and 3000 in areas with relief, but the difference becomes more pronounced in areas with relativley low relief. Because radius values are given in map units (ie. meters) then a value of 30 is only the four adjacent cells and not the full eight neighboorhood. To include the full eight neighboorhood it is possible to use the pythagorean theorem to solve for the distance from the center cell. This results in a distance of 42.4 m. However; I don't know exactly how geormophon algorithm accounts for cell centers so I think that I will just use radius values that are multiples of the cell size. 
 REM -METHOD, 0 = multiscale, 1 = line tracing. If 0, then use the -DLEVEL parameter, if 1 then use the -RADIUS parameter. 
 REM -DLEVEL, The multi-scale factor. A multi-scale factor of 3, 9, and 64 (with different -RADIUS just to check) did not make any difference in the results. However, a multiscale factor of 300 resulted in much more local results (it seems that the higher the dlevel the more local the results are). A factor of 3000 was too large on my test DEM so I just went with 300.   
REM processing notes: line tracing (radial limit = 32) and multiscale (9 and 32) had a correlation of 50.1% This is the largest difference between any of the parameters, thus it seems that this is a critical choice. Since they produce two very different results I think that I will do both. I will do one multiscale (-DLEVEL 3, since this parameters doesn't make much difference), and one small and one large -RADIUS
set geomorph_L=30 300 3000
for %%i in (%geomorph_L%) do (
echo now calculating geomorphons for radius %%i
saga_cmd ta_lighting 8 -DEM=%basedem% -GEOMORPHONS=%desFol%gmrph_radius_%%i.sgrd -THRESHOLD=1.000000 -RADIUS=%%i -METHOD=1
)
echo %date%:%time%
REM Multiscale Geomorphons
set geomorph_M=30 300
for %%i in (%geomorph_L%) do (
echo now calculating multiscale geomorphons
saga_cmd ta_lighting 8 -DEM=%basedem% -GEOMORPHONS=%desFol%gmrph_ms.sgrd -THRESHOLD=1.000000 -METHOD=0 -DLEVEL=3.0
)
echo %date%:%time%


REM Tool: Morphometric Features ##########
REM Uses a multi-scale approach by fitting quadratic parameters to any size window (via least squares) to derive slope, aspect and curvatures. This is the method as proposed and implemented by Jo Wood (1996) in LandSerf and GRASS GIS (r.param.scale). Slope is the magnitude of maximum gradient given for the steepest slope angle and measured in degrees. Profile curvature is the curvature intersecting with the plane defined by the Z axis and maximum gradient direction. Positive values describe convex profile curvature, negative values concave profile. Plan curvature is the horizontal curvature, intersecting with the XY plane. 
REM Longitudinal curvature is the profile curvature intersecting with the plane defined by the surface normal and maximum gradient direction. Cross-sectional curvature is the tangential curvature intersecting with the plane defined by the surface normal and a tangent to the contour - perpendicular to maximum gradient direction. Minimum curvature is measured in direction perpendicular to the direction of of maximum curvature. The maximum curvature is measured in any direction. 
REM input: elevation
REM Parameters:
 REM -SIZE: radius = size of processing window (N = 1 + 2r), where r is the radius given as number of cells. This seems like a different definition of neighborhood size than used in the other tools, but it works out the same. To prove this to myself it is possible to rearange the equation to solve for the radius' with a given neighborhood size ((N-1)/2) = r. Substituting the following neighborhood sizes (N) into the equation: 1, 2, 4, 8, 16, 32, 64; results in a radius of 0, 0.5, 1.5, 3.5, 7.5, 15.5, and 31.5. Rounding these to the nearest value results in an input radius of 1,2,4,8,16,32, approximatley the same as the neighborhood sizes used in the other tools (perhaps the other tools use the same neighborhood calculation?).  
 REM -TOL_SLOPE: slopes less than this will be considered flat
 REM -TOL_CURVE: curvatures less than this value will be considered flat.
 REM -EXPONENT:
 REM -ZSCALE: 
 REM -CONSTRAIN: 
for %%i in (%neighbors%) do ( 
echo now calculating multiscale morphometric features for a neighborhood of %%i 
saga_cmd ta_morphometry 23 -DEM=%basedem% -SLOPE=%desFol%sl_%%i.sgrd -PROFC=%desFol%profc_%%i.sgrd -PLANC=%desFol%planc_%%i.sgrd -LONGC=%desFol%longc_%%i.sgrd -CROSC=%desFol%crosc_%%i.sgrd -MAXIC=%desFol%maxc_%%i.sgrd -MINIC=%desFol%minc_%%i.sgrd -SIZE=%%i -TOL_SLOPE=1.000000 -TOL_CURVE=0.000100 -EXPONENT=0.000000 -ZSCALE=1.000000 -CONSTRAIN=0
)
echo %date%:%time%


REM Tool: Focal Statistics ##########
REM run for several Kernal_radius values. Radius values are given in number of cells
REM Kernel_type = 1 means circle, -Bcenter = 1 means include center cell, -DW_WEIGHTING=0 means no distance weighting
for %%i in (%neighbors%) do ( 
echo now calculating multiscale focal statistics for a size %%i neighborhood
saga_cmd statistics_grid 1 -GRID=%basedem% -MEAN=%desFol%meanelev_%%i.sgrd -MIN=%desFol%minelev_%%i.sgrd -DIFF=%desFol%diffmeanelev_%%i.sgrd -DEVMEAN=%desFol%devmeanelev_%%i.sgrd -BCENTER=1 -KERNEL_TYPE=1 -KERNEL_RADIUS=%%i -DW_WEIGHTING=0
)
echo %date%:%time%

REM NEED TO SUBTRACT the min and mean from base elevation to get relative elevation. Use the grid calculator
REM Tool: Grid Difference between min and mean with base elevation to get relative elevation
for %%i in (%neighbors%) do ( 
echo now calculating minimum relative elevation for a neighborhood of %%i
saga_cmd grid_calculus 3 -A=%basedem% -B=%desFol%minelev_%%i.sgrd -C=%desFol%relelev_%%i.sgrd

echo now calculating mean relative elevation for a neighborhood of %%i
saga_cmd grid_calculus 3 -A=%basedem% -B=%desFol%meanelev_%%i.sgrd -C=%desFol%relmeanelev_%%i.sgrd
)
echo %date%:%time%


REM Convergence Index (search radius) ##########
REM input: elevation
REM parameters:
REM choosing gradient (on/off) and difference (direction to the center cell or center cell's aspect direction didn't seem to have any effect on resulting values). Only the radius seems to have much of an influence.  
for %%i in (%neighbors%) do ( 
echo now calculating convergence index for a size %%i neighborhood
 saga_cmd ta_morphometry 2 -ELEVATION=%basedem% -CONVERGENCE=%desFol%ci_%%i.sgrd -SLOPE=0 -DIFFERENCE=0 -RADIUS=%%i -DW_WEIGHTING=0
)   
echo %date%:%time%

 
REM MultiScale Topographic Position Index ##########
REM Explanation: "The Topographic Position Index (TPI) compares the elevation of each cell in a DEM to the mean elevation of a specified neighborhood around that cell. The neighboorhood can be defined as an anulus (e.g., ring). Positive TPI values represent locations that are higher than the average of their surroundings, as defined by the neighborhood (ridges). Negative TPI values represent locations that are lower than their surroundings (valleys). TPI values near zero are either flat areas (where the slope is near zero) or areas of constant slope (where the slope of the point is significantly greater than zero)." (http://www.jennessent.com/downloads/tpi-poster-tnc_18x22.pdf). 
REM input: Elevation
REM parameters: 
 REM Minimum scale: Inner radius (in number of pixels). 
 REM Maximum Scale: Outer radius (in number of pixels).
 REM Number of Scales: The number of smaller 'rings' that the annulus is divided into. For example, a 30m DEM and a min scale of 1 and max scale of 64 sets a circular neighborhood with a radius of 1920m (30m * 64 cells). This distance is then divided into approximatley equal distances based on the number of scales parameter. In this example, with a scale of 3, TPI would be calculated over 1920m, then the annulus would be shrunken by 1/3 [] and TPI be calculated over this reduced distance. "This implementation calculates the TPI for different scales and integrates these into one single grid. The hierarchical integration is achieved by starting with the standardized TPI values of the largest scale, then adding standardized values from smaller scales where the (absolute) values from the smaller scale exceed those from the larger scale"
REM In a way I don't like the multiscale TPI because I like having more control of the specifics of the calculations. I tried combinations of min,max,scale of 1,2,2; 1,4,2; 1,8,2; 1,16,2; and 1,32,2. Correlations between combinations of these parameters (in order) were: 98, 93, 86, and 86. Thus it seems that the max distance doesn't have a huge influence on TPI values. I also investigated increasing the scale (with max distance = 16) using a 2, 3, and 16 scale. Correlations were > 98, thus I interpreted this that the number of scales didn't really matter. Visually, a TPI of 1,2,2 and 1,16,2 highlighted different features and had a correlation of 75, so I decided to use these values. This decision is a trade off between complexity and processing time. Since the max distance is 16 this does not consider distances > 480 m (30m * 16 cells). This is a limitation, but is necessary because max distances of 32 took a much longer time to process.
set maxscale=2 16
for %%i in (%maxscale%) do ( 
echo now calculating multiscale TPI for a size %%i neighborhood  
saga_cmd ta_morphometry 28 -DEM=%basedem% -TPI=%desFol%tpi_%%i -SCALE_MIN=1 -SCALE_MAX=%%i -SCALE_NUM=2
) 
echo %date%:%time% 
	
	
REM Terrain Ruggedness Index ##########
REM Explanation:
REM input: elevation
REM parameters:
 REM radius in cells
 REM mode 0 = square, 1 = circle
for %%i in (%neighbors%) do ( 
echo now calculating terrain rugedness index for a size %%i neighborhood
  saga_cmd ta_morphometry 16 -DEM=%basedem% -TRI=%desFol%tri_%%i.sgrd -MODE=1 -RADIUS=%%i
)
echo %date%:%time%

 
REM Terrain Surface Convexity ##########
REM Explanation:
REM input: elevation
REM parameters:
 REM KERNEL=1 conventional eight neigboorhood 
 REM TYPE=0 convexity (type=1 concavity). They are recipricols of each other. 
 REM EPSILON=0.010000 flat area threshold
 REM SCALE=10 number of cells
 REM METHOD=1 resampling (method=0 counting cells). I didn't detect any difference in this parameter
 REM DW_WEIGHTING, -DW_BANDWIDTH (these parameters only useful if kernal = 2 (eight neigboorhood distance based weighting).  

for %%i in (%neighbors%) do (
echo now calculating terrain surface convexity for a size %%i neighborhood
 saga_cmd ta_morphometry 21 -DEM=%basedem% -CONVEXITY=%desFol%convx_%%i.sgrd -KERNEL=1 -TYPE=0 -EPSILON=0.010000 -SCALE=%%i -METHOD=1
 )
echo %date%:%time% 
  
  
REM Mass Balance Index ##########
REM Explanation:
REM input: elevation
REM parameters:
 REM TSLOPE = transformed slope. With Tcurve set to 0.01, I tried Tslope values of 1, 5, 15, 25. The correlation between a TSlope of 1 and the other slope thresholds was 99, 98, and 98 (5, 15, 25). Thus I concluded that this parameter was not very impactful in an area of moderate relief. 
 REM Tcurve = transformed curvature. With Tslope set to 15, I tried Tcurve values of 0.001, 0.01, 0.1. The correlation was 87.9 and 77.8 (but sigmoid in shape) between 0.001 and 0.01, and 0.1. This parameter seems to have more influence than Tslope.
 REM Tslope of 1 and Tcurve of 0.001 and Tslope of 25 and Tcurve of 0.1 produced a sigmoid correlation of 77.6 (pretty much the same as between the two Tcurve values. Thus this seems worth running with the two extreme curvature values. However; I think that an intermediate value might have more influence in flatter areas so I used three values.  
 REM THREL Transformed vertical distance to channel network. I don't think that I need this since vertical distance to channel network is not used, and in fact this has no influence on the resulting values.
set tcurve=0.001 0.01 0.1
for %%i in (%tcurve%) do (
echo now calculating mass balance index for a curvature of %%i
saga_cmd ta_morphometry 10 -DEM=%basedem% -MBI=%desFol%mbi_%%i.sgrd -TSLOPE=15.0 -TCURVE=%%i
)
echo %date%:%time%


	
REM Saga wetness index, catchment area, modified catchment area, and catchment slope ##########
REM Explanation: SWI = lower values = wetter.
 REM input: Elevation 
 REM parameters:
	REM Some explanation of parameters, but didn't match my experience https://gis.stackexchange.com/questions/304535/choosing-parameters-for-saga-wetness-index
	REM -SUCTION; set suction 1 10 100 etc. (1 is too low because it results in a null modified catchment area raster). probably worth starting with 10 and then increasing  to 1000 then 10000). Changing suction does not change catchment area or catchment slope, but it drastically changes the modified catchment area. Smaller values means higher suction. Smaller values result in a higher wetness index values. I decided to run this with only extreme values 10 and 10000 because the correlation between the other suction values were fairly high and because this takes so long to run that I want to minimize run time. 
	REM _AREA_TYPE; Type of Area: 0 = total catchment area, 1 = square root of catchment area, 2 = specific catchment area. I tested these and found that the choice of this parameter has absolutlely no effect on the catchment area, the modified catchment area, or (unsurprisingly) catchment slope. It had only a minor efect on the wetness index. Since TWI and SPI need specific catchment area as input, I chose to use specific catchment area.   
	REM -SLOPE_TYPE; Type of slope: catchment slope is (I think) the average slope of the catchment area. Local slope is the slope for each cell. I found that local slope was visually a better choice because it produced wetness patterns that were more consistent with the landscape. In particular, I found that local slope better represented stream channels than did catchment slope. Local slope also produced more intuitive wetness patterns so I'm going with local slope. 
	REM -SLOPE_MIN; Minimum slope: "all values smaller than this value will be set to this value. A smaller value, e.g. 0, leads to higher WI maximum values" (webpage above). I chose to leave this as zero since I thought this was the most reproducible across large areas.  
	REM -SLOPE_OFF; Offset slope: A small value added to each slope. I'm fairly sure that this is just to avoid division by zero in the wetness index calculation. Default is 0.1, but I chose to set to 0.01. This does have an effect on the wettest areas, but does increase all index values slightly (generally in the second decimal place for drier areas, a larger increase in wetter areas - sometimes as much as 1.4 units at the outlet of a HUC 12). I think that a smaller number is better because it is closer to the actual slope if the slope is zero.   
	REM -SLOPE_WEIGHT; Slope weighting = I think this is if you want slope to have more importance in the calculation. Left as 1 (no weighting). 
REM Notes: Using different suctions results in creating the catchment area and catchment slope twice, but it is relativley quick. Since the output is the same, the catchment area and slope from the second run overwrites the output from the first run. It would be very convienent if it were possible to specify an existing dataset as input to the catchment area and slope to avoid double calculation, but this is not possible.   
set suction=10 10000
for %%i in (%suction%) do (
echo now calculating SWI for a suction of %%i 
saga_cmd ta_hydrology 15 -DEM=%basedem% -WEIGHT=NULL -AREA=%desFol%ca.sgrd -SLOPE=%desFol%cs.sgrd -AREA_MOD=%desFol%mca_%%i.sgrd -TWI=%desFol%swi_%%i.sgrd -SUCTION=%%i -AREA_TYPE=2 -SLOPE_TYPE=0 -SLOPE_MIN=0.000000 -SLOPE_OFF=0.010000 -SLOPE_WEIGHT=1.000000
)
echo %date%:%time%


REM Topographic wetness index ##########
REM Explanation: 
REM input: slope (in radians), catchment area (in specific catchment area). 
REM parameters:
 REM slope must be in units of radians (-UNIT_SLOPE = 0)
 REM -METHOD=1 is maximum triangle slope (Tarboton 1997, I favor this because Tarboton was on my graduate committee, but there are other options)
saga_cmd ta_morphometry 0 -ELEVATION=%basedem% -SLOPE=%desFol%slopeRadians.sgrd -METHOD=1 -UNIT_SLOPE=0
 REM catchment area can be taken from the saga output. It doesn't really matter which suction is used for the catchment area calculation because the output is the same. 
 REM area converstion 0) no converstion (areas already given as specific catchment area), 1) 1/cell size (psuedo specific catchment area). The choice of these options depends on how you catchment area in other tools. 
 REM Method: 0)standard, 1) topmodel. Don't know the difference but I'm going with standard. 
 REM no other parameters given since catchment area is not likely to change 
echo no calculating topographic wetness index
saga_cmd ta_hydrology 20 -SLOPE=%desFol%slopeRadians.sgrd -AREA=%desFol%ca.sgrd -TRANS=NULL -TWI=%desFol%twi.sgrd -CONV=0 -METHOD=0
echo %date%:%time%


REM Stream Power Index ##########
REM Explanation:
REM input: slope (units of radians) and catchment area (as specific catchment area)
REM Parameters:
 REM -CONV; Area Conversion. 0 = no conversion (areas already give as specific catchment area, 1 = 1/cell size (psuedo specific catchment area). Since specific catchment area is already generated, set -CONV=0. 
echo now calculating stream power index 
saga_cmd ta_hydrology 21 -SLOPE=%desFol%slopeRadians.sgrd -AREA=%desFol%ca.sgrd -SPI=%desFol%spi.sgrd -CONV=0
echo %date%:%time%


REM Vector Rugedness Measure
REM Explanation: This "quantifies terrain ruggedness by measuring the variation in a three-dimensional orientation of grid cells within a moving window. Slope and aspect are decomposed into 3-dimensional vector components (in the x, y, and z directions) using standard vector analysis in a user-specified moving window size (3x3). The vector ruggedness measure quantifies local variation of slope in the terrain more independently than the topographic position index and terrain ruggedness index methods. Values range from 0 to 1 in flat to rugged regions, respectively" (Amatulli et al 2019. Geomorpho90m). 
REM input: Elevation 
REM Parameters
	REM -MODE; 0=square, 1 = circle. I chose a circle because it seems more intuiative and it was the default. 
	REM -RADIUS; Radius in number of cells. I think that this makes sense to use the same neighborhood as other covariates. I tested a radius of 300, but that ran SUPER slow. 
	REM -DW_WEIGHTING; distance weighting. 0 = no weighting, 1 = inverse distance to a power, 2 = exponential, 3 = gaussian. No reason to choose any of these weighting schemes. Choosing anything other than 0 allows the specification of individual parameters for each weighting scheme. 
REM Output: Vector Ruggedness Measure
for %%i in (%neighbors%) do (
echo now calculating VRM for a radius of %%i 
saga_cmd ta_morphometry 17 -DEM=%basedem% -VRM=%desFol%vrm_%%i.sgrd -MODE=1 -RADIUS=%%i -DW_WEIGHTING=0
)
echo %date%:%time%

REM ####### Compress files and convert to .tif.  This achieves about a 60% compression ratio. Because this achieves such a good compression I am somewhat hesitant to consider converting everything from float to integer (UInt16 or INT16) for a few reasons even though this is advocated by some of the group. 
REM The main reason is that converting format types is convienent for reducing file sizes for storing and sharing, but the compression already does a pretty good job. 
REM Secondly, users will have to (or at least should) reconvert all files to their original units to use these, which necessitates needing large file sizes anyway. 
REM Thirdly, I anticipate that most users of this data will only download a few HUCs that they are interested in and not the entire dataset. I anticipate that the few HUCs needed wont be a huge burden anyway. 
REM Fourthly, those of use who want the whole dataset probably already have the storage and computational power to handle all of this. 
REM Finally, applying a conversion could be done with Travis script, but I don't have the time or skill to put this on the HPC right now and I just want to get this done. 

REM Compress geomorphons first because they are byte instead of float32. I'm using packbits because it has a fairly good compression ratio, but relativley fast read speed for byte format. 
REM https://kokoalberti.com/articles/geotiff-compression-optimization-guide/
set geomorphs= gmrph_ms.sdat gmrph_radius_3.sdat gmrph_radius_90.sdat
for %%x in (%geomorphs%) do (
echo now converting and compressing %%x
gdalwarp -co NUM_THREADS=ALL_CPUS -co COMPRESS=PACKBITS -co TILED=YES -tr 30 30 -r cubic %%x %desFol%%%~nx.tif
)

REM Remove geomorphons saga grid files. This is important because then I can just run next compression commands without having to figure out how to filter these from the *.sdat search. 
set geomorphs=gmrph_ms.sdat gmrph_ms.sgrd gmrph_ms.prj gmrph_ms.mgrd gmrph_radius_3.sdat gmrph_radius_3.sgrd gmrph_radius_3.prj gmrph_radius_3.mgrd gmrph_radius_90.sdat gmrph_radius_90.sgrd gmrph_radius_90.prj gmrph_radius_90.mgrd
for %%x in (%geomorphs%) do (
echo now removing %%x
del %%x
)


REM Compress all other covariates
REM %%x is the iterator of the full file name
REM %%~nx just means the file name without the extension. 
setlocal enabledelayedexpansion enableextensions
for /f %%x in ('dir /b *.sdat') do (
echo now converting and compressing %%x 
REM COMPRESS=ZTSD -co PREDICTOR=3 and ZLEVEL=9 writes at the same speed and achieves about the same compression ratio as compress=deflate, but reads much faster. However; DO NOT USE IT as the r raster package can not read it! I tested multiple compression algorithms, but COMPRESS=DEFLATE, PREDICTOR=3 achieves a compression almost as good at ZSTD. 
gdalwarp -co NUM_THREADS=ALL_CPUS -co COMPRESS=DEFLATE -co PREDICTOR=3 -co TILED=YES -tr 30 30 -r cubic %%x %desFol%%%~nx.tif
)

REM Remove intermediate saga grid files since I only want geotiffs.
setlocal enabledelayedexpansion enableextensions
for /f %%x in ('dir /b *.sdat *.mgrd *.sgrd *.prj') do (
echo now removing %%x
del %%x
)

echo Start Time: %startTime%
echo Finish Time: %date%:%time%



REM ---------------
REM Tools that I did not use

REM MRVBF and MRRTF ##########
REM Explanation: Stuff. These calculations are exceptionally influenced by the nodata value when converting from tiff to saga grid format. It seems like this calculation does not recongize nodata values properly.  
REM input: -DEM: Elevation
REM parameters:
 REM There are too many parameters to modify and these are probably best adapted to match a specific landscape, so just ran with defaults. 
 REM -T_SLOPE - this should be changed for the grid cell size. 15 is appropriate for 30 m. See page 3, https://www.nrcs.usda.gov/wps/PA_NRCSConsumption/download?cid=stelprdb1258050&ext=pdf
REM echo now calculating MRVBF and MRRTF  
REM saga_cmd ta_morphometry 8 -DEM=%basedem% -MRVBF=%desFol%mrvbf.sgrd -MRRTF=%desFol%mrrtf.sgrd -T_SLOPE=15 
REM echo %date%:%time%

REM Relative Heights and Slope Positions
REM This tool produces relative heights that are mainly focused on topo-climatology. I think that some of these could be useful for DSM, but I have decided to not produce these because the documentation is so very poor and I can't really understand the output. Here is what I think though: Slope Height (no idea), Valley Depth (not sure how this is different than the specific tool), Normalized height (relative height between zero (low) and one (high) with in a drainage, no idea how a drainage is defined), standardized height (elevation * normalized height?), mid-slope position (0 is midslope, 1 is either bottom of drainage or top of ridge). 
REM Further explanation can be found at:
 REM https://gis.stackexchange.com/questions/154172/saga-tool-relative-heights-and-slope-positions-what-do-results-tell-me
 REM http://sourceforge.net/projects/saga-gis/files/SAGA%20-%20Documentation/HBPL19/hbpl19_05.pdf/download?use_mirror=kent
 REM PDF link in the tool. 
REM Input: ELEVATION
REM parameters: w, t, e (see links above for further explanation). 
 REM Results of exeriments on a HUC 12 watershed in New Mexico. 
 REM w set to 0.5, 0.1, 1; t kept at 10, e kept at 2. Changing values of w had no influence on any of the outputs (all correlations > 99 between different w settings).
 REM t set to 1, 10, 100; w kept at 0.5, e kept at 2. t = 1 ran for a long time but produced only a single value for each output. smaller values of t increase run time dramatically. Changing values of t had little influence on the outputs (r2 > 91) except for midslope position (r2 > 73). 
 REM e set to 0.2, 2, 20; w kept at 0.5, t kept at 100. e = 20 produced NaN. e of 0.2 and 2 produced the following correlations between parameter values for each output: slope height (r2 > 97), valley depth (r2 > 88), nomralized height (r2 > 86), standardized height (r2 > 95), midslope position (r2 > 68). 

REM REM LS Factor
REM LS Factor requires slope and catchment area. I decided against this because I feel that the input parameters (rill/interrill erosivity and stability) are mostly site-specific . Also, this is meant for run off modeling, not digital soil mapping or geomorphological mapping so it doesn't make a whole lot of sense to calculate it.  

REM Morphometric Protection Index 
REM MPI is the same as positive openness according to the SAGA tool reference. Did not use since the positive openess tool gives both positivie and negative openess.  

REM Melton Ruggedness Index
REM this index is "According to Melton (1965), is a slope index that provides specialized representation of relief ruggedness within the basin". This index has been found useful for discriminating fluvial fans from debries-flow fans (Marchi and Fontana 2005).
REM input: ELEVATION
REM parameters: none (an empirical equation is used as the calculation). This equation, from Melton 1965 is: MRn= H-h / A^0.5. Where, H = maximum elevation, h = minimum elevation, A = area of the basin. 
REM Output Melton ruggedness Number, Catchment ARea (derived using the D8 algorithm), and Maximum height (this is the maximum height of the DEM minus the elevation at each grid cell. I think that this is useful for tracking where semidment is likely being transported or for identifying where the sediment is coming from). I think this is an interesting derivative, but I'm going to leave it out because I could probably calculate this better using a multiple flow direction alrogithm. This would be cool to investigate on the Jornada. 

REM Analytical hillshades
 REM I did however, choose to create two analytical hillshades for the winter and summer solstice. My thought is that these will have use in microclimatology. The summer solstice should represent the most heating, while the winter solstice represents the coldest areas. I chose to use 2021 just because. Except that they didn't work via the commandline. These are probably adaquately addressed with the potential incoming solar radiation tools instead.  
REM REM This is cool, but it doesn't work because the commandline won't read the right projection. Oh Well, this is probably captured by the potential incoming solar radiation just fine. 
REM saga_cmd ta_lighting 0 -ELEVATION=%basedem% -SHADE=%desFol%anltc_hs_ws.sgrd -METHOD=0 -POSITION=1 -DATE=2020-12-21 -TIME=12.000000 -EXAGGERATION=1.000000 -UNIT=1
REM saga_cmd ta_lighting 0 -ELEVATION=%basedem% -SHADE=%desFol%anltc_hs_ss.sgrd -METHOD=0 -POSITION=1 -DATE=2020-06-21 -TIME=12.000000 -EXAGGERATION=1.000000 -UNIT=1


REM Standard Deviation of Curvature (seems to work well in glacial till). Base curvature from a 1 cell neighborhood.
REM This takes a very long time and does not produce sensible output (just random circles). 
REM for %%i in (%neighbors%) do (
REM echo now calculating Standard Deviation of Curvature for a size %%i neighborhood
REM saga_cmd statistics_grid 1 -GRID=%desFol%profc_1.sgrd -STDDEV=%desFol%stddev_profcurv_%%i.sgrd -BCENTER=1 -KERNEL_TYPE=1 -KERNEL_RADIUS=%%i -DW_WEIGHTING=0
REM saga_cmd statistics_grid 1 -GRID=%desFol%planc_1.sgrd -STDDEV=%desFol%stddev_plancurv_%%i.sgrd -BCENTER=1 -KERNEL_TYPE=1 -KERNEL_RADIUS=%%i -DW_WEIGHTING=0
REM )


REM Tool: Potential Annual Insolation
REM this tool is much simpler interface than the Potential incoming solar radiation tool. However; it creates a Saga Grid collection as output. Unfortunatley, gdal can not read a saga gis grid collection to convert it to geotif. This is not a super huge issue except that I want to keep all grids as geotif (and converting to tif allows me to compress the files somewhat better). Since this tool just seems to call the Potential Incoming Solar Radiation tool (with a few defaults) I use the potential incoming solar radiation tool instead of this tool. 
REM Inputs: ELEVATION
REM Parameters: 
 REM Number of steps = how many days in each step increment (12 = once a month)
 REM UNITS = 0 = kWh/m2, 1 = kJ/m2, 2 = J/cm2
 REM Resolution = hours (time step size for a days calculation)
 REM Reference Year = year to calculate for
REM Output potential annual insolation for each month in units of kWh/m2. Each grid in the stack coresponds to the 1st of each month. Higher values indicate that the cell will have a higher potential annual insolation.
REM echo now calculating potential annual insolation
REM saga_cmd ta_lighting 7 -DEM=%basedem% -INSOLATION=%desFol%pai.sdat -STEPS=11 -UNITS=0 -HOUR_STEP=4 -YEAR=2020


REM Compound Analysis
 REM it is possible to use compound analysis to quickly generate a large number of covariates, but I found that the indivudal tools gave me much more control. Also, just using compound analysis for one tool actually creates everything (even if you don't want it to) so it is slow. 
 REM The following are some notes about how to calculate Verticle distance to channel network using the compound analysis tool. 
 REM As best as I can tell, this tool uses the "channel network and watershed" tool finds junction nodes where channels join and then uses these junction nodes to interpolate a 'base-level DEM'. This base level DEM is subtracted from the original DEM to create the output. Unfortunatley the base-level interpolation has some issues and does not keep the base level below the DEM resulting in areas with negative values in the output. This is most egregious at a strahler order = 1, so I only calculate this for a shrahler order of >=2. The easiest way to solve this is just to set all negative values to zero (these values should be approximatley zero so this works). This does not quite remove all of the artifacts, but it does a great job.  

	REM REM Inputs: Elevation
	REM REM Parameters: -THRESHOLD = Strahler order. 
	REM REM Output: -CHANNELS=the channel network, -CHNL_BASE=base level DEM -CHNL_DIST= vertical distance above channel network. Creating teh channels and the channel baselevel is mostly for transparency. I do not anticipate these to be useful for DSM. 
	REM set orders=2 3 4 5 6 7 
	REM for %%i in (%orders%) do (
	REM echo now calculating vertical distance above channel network for strahler order of %%i
	REM saga_cmd ta_compound 0 -ELEVATION=%basedem% -CHANNELS=%desFol%channels_%%i.shp -CHNL_BASE=%desFol%chnl_bse_%%i.sgrd -CHNL_DIST=%desFol%vdcn_%%i.sgrd -THRESHOLD=%%i
	REM )


	REM REM Change grid values. The vertical distance to channel network grid from the basic terrain analysis tool has a number of negative values because of the way that the base level interpolation is handled. Change these values to 0, which is what they should be. 
	REM set orders=2 3 4 5 6 7
	REM for %%i in (%orders%) do (
	REM saga_cmd grid_tools 12 -INPUT=%desFol%vdcn_%%i.sgrd -OUTPUT=%desFol%vdcn_%%i.sgrd -METHOD=1 -RANGE=%desFol%.lut_reclass.txt
	REM )


		
	
