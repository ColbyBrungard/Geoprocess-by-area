# Geoprocess DEMs by watershed.

This project is for calculating many derivatives from a DEM for digital soil mapping.

This project takes a DEM as input, splits the DEM by watershed (with 100 cell buffer), and then smooths the subset DEM. Multiple derivatives are then calculated for each watershed, and the derivatives are trimmed back to a 20 cell buffer from the original watershed to avoid edge contamination but to leave enough to feather when mosaicking back together. Intermediate processing data/files are deleted to save storage space. This code does NOT hydrologically correct DEMs (i.e., fill) because I found that filling the DEM's produced 'flat' areas in the center of basins. 

The reason that I took this approach is because I was running into memory issues when trying to calculate derivatives from a 5-m DEM over the state of New Mexico. To solve this I needed a way to tile the DEM in such a way that made physical sense and created hydrologically sound derivatives (I thought that square tiles would produce spurious flow routing values). 


## Getting Started

To run this code:  
1. install OSGeo4W available at: https://trac.osgeo.org/osgeo4w/ 
2. download SagaGIS from: https://sourceforge.net/projects/saga-gis/files/ (this code tested with Saga 6.0.2_x64) 
3. download and open geoprocessV3.X.bat (this is a batch file, don't double click) (I like Notepadd ++) and change the following (text inside parentheses is for annotation only and should not be included in your file):
	* set PATH=%PATH%;C:\saga-6.2.0_x64 (change the directory after the " %PATH%," to the location of where saga_cmd.exe is located)
	* SET SAGA_MLB=C:\saga-6.2.0_x64\tools (make sure the directory matches the directory above)
	
	* set DEM=C:\DEM\testDEM2.tif (name of full path to DEM)
	
	* set indexA=c:\DEM\wbdhu8_a_us_september2017.shp (path to watershed shapefile. The shapefile and the DEM MUST be in the same projection).
	* set indexB=C:\DEM\wbdhu8_a_us_september2017_proj.shp (path to projected watershed shapefile, I used albers equal area)
	
	* set tiles=13030103 (The number of each polygon. Manually input a space separated vector of values for each polygon, these should be single values (not words) and contain NO spaces. This can easily be generated using the R commands below.
 	
	* set fieldname=HUC8 (The column name of the shapefile attribute table with the watershed values) 
	
	* set bufferA=100 (the buffer distance used to clip the DEM around each shapefile)
	* set bufferB=20 (the buffer distanced used to trim each derivative)

```r
require(rgdal)
setwd("C:/DEM")
# Read SHAPEFILE.shp from the current working directory (".")
 shape <- readOGR(dsn = ".", layer = "wbdhu8_a_us_september2017")
 hu8 <- as.numeric(as.character(shape@data$HUC8))
# Write to file
 cat(hu8, file="./HUC8.txt")
```	
 
5. review the list of derivatives (below), if there are some that you do not want, navigate to the code section that creates these derivatives (see in-file comments), and block comment-out these sections (REM is the comment flag in .bat files)
	
6. open OSGeo4W, navigate to the folder where this file is located (cd command), type the file name (i.e., GeoprocessV3.1.bat), and hit enter.  

7.  let this run. it will take some time to process depending on the size of the input DEM. 
 
Note: I decided not to do this in R, because at the time I initiated this project, the RSAGA package no longer communicated with the latest versions of SAGA and the latest SAGA versions had several derivatives that were not available in SAGA 2.0X  	

### Prerequisites
OSGeo4W must be downloaded and installed, 
SAGA GIS must be downloaded

### Covariates
The following covariates are derived from the input DEM.

| Number | File Extention | Definition |
| --- | --- | --- | 
| 1.    | s     | smoothed elevation |
| 2.    | hs    | Hillshade |
| 3.    | sl    | Slope |
| 4.    | profc | Profile Curvature |
| 5.    | planc | Plan Curvature |
| 6.    | lc    | Longitudinal Curvature |
| 7.    | cc    | Cross-Sectional Curvature |
| 8.    | mc    | Min Curvature |
| 9.	| mxc   | Max Curvature |
| 10.	| tc    | Total Curvature |
| 11.	| mbi   | Mass Balance Index |
| 12.	| ci    | Convergence Index |
| 13.	| dah   | Diurnal anisotropic heating |
| 14.	| tpi   | Multi-Scale Topographic Position Index |
| 15.	| mrvbf | Multiresolution valley bottom flatness |
| 16.	| mrrtf | Multiresolution ridge top flatness |
| 17.	| tri   | Terrain Ruggedness Index |
| 18.	| tsc   | Terrain Surface Convexity |  
| 19.	| ca    | Catchment Area |
| 20.   | cs    | Catchment Slope |
| 21.	| mca   | Modified Catchment Area |
| 22.	| swi   | Saga Wetness Index |
| 23.	| po    | Positive openness |
| 24.   | spi   | Stream Power Index |
| 25.   | twi   | Topographic wetness index |


### Settings and thoughts on saga modules that were used.

A. Smoothing: circle-shaped smooting filter with radius of 4 cells 

C. Analytical hillshade: Azimuth = 315, declination = 45 (default parameters)

D. Slope calculated using the D-inf (Tarboton, 1997), and is in percent. Profile, plan, longitudinal, cross, minimum, maximum, and total curvature calculated using Zevenbergen and Thorne 1987 method. I tried calculating flow-line curvature, but it never produced an output (even with slope set to the correct units of percent).  

E. Convergence index: neighbors = 3x3, method = gradient. "The index is obtained by averaging the bias of the slope directions of the adjacent calls from the direction of the central cell, and subtracting 90 degrees. The possible values of the index range from -90 to +90 degrees. Values for a cell where all eight neighbors drain to the cell (pit) are -90, values for a cell where all eight neighbors drain away from the cell center (peak) is 90, values for a cell where all eight neighbors drain to one direction are 0." From: Kiss, R (2004). Determination of drainage network in digital elevation models, utilities and limitations, Journal of Hungarian Geomathematics, 2, 16-29.)

F. Diurnal Anisotropic Heating. The angle is set to 225 which is a southwest angle.
 
G. MultiScale Topographic Position Index. Default parameters (scale_min, scale_Max, scale_num) seemed good to me. I rather like this as it seems to pull out differences in the age of alluvial fans. 

H. MRVBF/MRTTF http://onlinelibrary.wiley.com/doi/10.1029/2002WR001426/abstract. Intended for separating erosional and depositional areas. Valley bottoms = depositional areas. MRVBF: higher values indicate that this is more likely a valley bottom. MRRTF: higher values indicate more likely a ridge. "While MRVBF is a continuous measure, it naturally divides into classes corresponding to the different resolutions and slope thresholds. Values less than 0.5 are not valley bottom areas. Values from 0.5 to 1.5 are considered to be the steepest and smallest resolvable valley bottoms for 25 m DEMs. Flatter and larger valley bottoms are represented by values from 1.5 to 2.5, 2.5 to 3.5, and so on". According to the paper, T_Slope was set to 32 based on DEM resolution (10 m). All other parameters were left to default values as suggested by the paper (section 5.4).   

I. Terrain Ruggedness Index. Which areas are the most rugged. "Calculates the sum change in elevation between a grid cell and its eight neighbor grid cells. I chose a radius of 10 cells (so for a 5 m DEM, 10x5 = 50m (or 100 m diameter)), and a circular mode. https://www.researchgate.net/publication/259011943_A_Terrain_Ruggedness_Index_that_Quantifies_Topographic_Heterogeneity 

J. Terrain Surface Convexity. Had to take the defaults since I couldn't get access to the paper. Probably a bad idea. Kernel 1 = eight neighborhood 

K. Saga wetness index. Kept all defaults as is.

L. Positive Topographic Openness: I'm not sure this makes much sense in an arid environment, but since it was intended to be input for geomorphological mapping I thought it might be interesting. Note, this calculation depends on a search radius (denoted L) over which the pixel is determined to be positive or negativley open. "larger values of L will highlight larger features and smaller L smaller forms". I tested several radii including 1x the DEM resolution, 5x the DEM resolution, 10x the DEM resolution and 100x the DEM resolution. I found absolutly no difference between 10x and 100x the the DEM resolution, while 1x and 5x were fairly visually similar (values were pretty similar too). However; I did feel that 1x the DEM resolution captured too much noise. I eventually decided that 10x the DEM resolution was the best radius to select as this seemed to highlight ridges and alluvial fan features when tested in mountains and bajadas. This publication best explains openess (Fig. 5 is particularly useful): Yokoyama, R. / Shirasawa, M. / Pike, R.J. (2002): Visualizing topography by openness: A new application of image processing to digital elevation models. Photogrammetric Engineering and Remote Sensing, Vol.68, pp.251-266. If you are using a different DEM resolution than 10m you will need to change the -RADIUS flag in the code.  

M. Mass balance index. Used default parameters: -TSLOPE=15.000000 -TCURVE=0.010000 -THREL=15.000000. http://onlinelibrary.wiley.com/doi/10.1002/jpln.200625039/pdf . The intent of this covariate is to identify areas of potential net sediment deposition (negative values) and areas of potential net erosion (positive values). Areas with a net zero balance between erosion and deposition will have values close to zero. Based on a visual review, to me this seems to nicely capture (on a very local scale) the difference in sholder (positive values), foot/toe slopes (negative values) and summit/backslope areas (areas near zero). According to the paper: "The mass-balance index is derived from transformed f(k, ht, n)values (Eq. 1). As shown in Fig. 2a, high positive MBI values occur at convex terrain forms, like upper slopes and crests, while lower MBI values are associated with valley areas and concave zones at lower slopes. Balanced MBI values close to zero can be found in midslope zones and mean a location of no net loss or net accumulation of material."

### Thoughts on saga modules that I didn't use. 

A. Morphometric Protection Index took a long time to run and then never produced a result. I'm also not sure what it would be good for. Maybe detecting sinkholes? 
  
B. Use ta_morphometry 23 to calculate standard derivatives (slope, etc.) using larger cell sizes.

C. I want to use the Wind Effect (Windward/Leeward Index) as I think it may be useful as a predictor (in the southwest), but I think that I need to use a grid of wind directions. 
 
D. I decided against calculating the vector ruggedness measure (https://onlinelibrary.wiley.com/doi/epdf/10.2193/2005-723), because the intent of this algorithm is to quantify landscape ruggedness for species (big horn sheep) modeling and this didn't seem relevant to soil development.
 
E. Wind Exposition Index (https://www.earth-syst-dynam.net/6/61/2015/esd-6-61-2015.pdf) this seems more intended for rain shadow effects and climate downscaling than digital soil mapping and I decided against it. However; it probably has some predictive power for large scale modeling. I did run it in the GUI (it takes ~ 30 min for a HUC 12 watershed) and I don't see much utility in it.  

F. SaLEM model is meant for escarpment modeling of initially flat terrain. I suppose that this might work for valley borders along the Rio Grande, but maybe not useful since I'm not dealing with bedrock, but deposited sediment. 

G. Compound analysis - Useful for Channel Network Base level, channels, relative slope position, but it is broken. Tried commandline and gui and it just hung up trying to calculate vertical distance to channel. 

H. Vertical Distance to Channel Network - requires channel network, which I can probably get from ta_compound 0, but which may give me relative elevation

I. Terrain surface texture. Defaults parameters (epsilon=1, scale=10, method=1, DW_weighting=3, DW_bandwith=0.7) only produced non-sensible results (circles of high values), but I don't know how exactly what the parameters should be changed to. 

J. Downslope Distance Gradient - how far downslope does one have to go to descend d meters?, http://onlinelibrary.wiley.com/doi/10.1029/2004WR003130/full. This seems like it could be useful for modeling soil depth, probably in humid environments, but after testing it (with d (distance) = 5, the resolution of the DEM) I found that I couldn't determine what the spatial pattern was. I also found that it wasn't continious so that after 5=m the calculation would start again resulting in a 'chunky' pattern. Even if this was a usuful covariate it would produce patterns (in the soil maps) that would (I feel) be incorrect.  

K. Slope height. This appears to be the inverse of valley depth, but I didn't find it very useful because I found that both ridges and valley bottoms had approximatly the same values and just didn't seem logical. 

L. Local, Upslope and downslope curvature. https://www.sciencedirect.com/science/article/pii/009830049190048I. Decided against using using these because these are the "the distance weighted average local curvature in a cell's upslope contributing area" (http://www.saga-gis.org/saga_tool_doc/2.2.7/ta_morphometry_26.html) and I couldn't figure out why local curvature using the weighted average upslope (and downslope) curvature would be all that useful for digital soil mapping. Also, they were highly correlated with cross curvature and seemed fairly redundant. Local curvature was highly correlated with cross and longitudinal curvature.

M. Curvatures: Tangential curvature. Same as Plan curvature. General curvature. Highly correlated with cross curvature and I don't understand general curvaure like I do cross curvature.

N. Relative heights and slope positions. I think that these are very interesting derivatives, they just didn't run when scripting, so probably need to derive these in the GUI. Didn't see much reason to change the default settings (W=0.5, T=10, E=2). 'W: The parameter weights the influence of catchment size on relative elevation (inversely proportional). T: The parameter controls the amount by which a maximum in the neighbourhood of a cell is taken over into the cell (considering the local slope between the cells). The smaller 't' and/or the smaller the slope, the more of the maximum value is taken over into the cell. This results in a greater generalization/smoothing of the result. The greater 't' and/or the higher the slope, the less is taken over into the cell and the result will show a more irregular pattern caused by small changes in elevation between the cells. E: The parameter controls the position of relative height maxima as a function of slope.' See https://gis.stackexchange.com/questions/154172/saga-tool-relative-heights-and-slope-positions-what-do-results-tell-me for more details. The following explanations are taken from: Boehner, J. and Selige, T. (2006): Spatial prediction of soil attributes using terrain analysis and climate regionalisation. In: Boehner, J., McCloy, K.R., Strobl, J. [Ed.]: SAGA - Analysis and Modelling Applications, Goettinger Geographische Abhandlungen, Goettingen: 13-28. (find this online on the saga homepage also on research gate). 
	* Normalized height is the vertical offset between the grid cell to its according channel line considering the catchment area of a particular point and is scaled from 0 to 1, where values close to one are higher localized areas and values close to 0 are lower positions. I found this to be particularly useful in distinquishing alluvial fans (and variations within fans) from the channels. I'm unsure how helpful this will be in mountinous terrain. I do not calculate standardized height as this just rescales normalized height by multiplying by actual elevation. I found that an index (0-1) made more sense.  

	* Midslope position is a quantification of the middle distance between ridge crest and valley. Midslope positions are assigned a value of 0, while ridge and valley positions are assigned values closer to 1. I believe that this may be an important predictor in mountinous terrain where it may approximate the middle 1/3 of the mountain slopes used to describe the geomorphic position in the field book for sampling and describing soils. This was originally intended to be used for modeling cold air drainage to identify the midslope positions that are likely to be the warmest so possibly this may also describe something about vegetation which may influence soil development. Also note, that if you symbolize this variable with a red-blue color scheme you can get a pattern quite reminiscient of 1960's psychedelic rock album cover. 
	
	* Valley depth (also called height below crest line) is the relative height of the grid cell to the nearest ridge/peak. Greater values indicate greater relief between the grid cell and the highest elevation. I believe that the highest elevation is determined by the specific catchment area for each cell.  

O. Negative topographic openness: This calculates openness as if viewed from below the land surface, which I didn't find particularly useful (see fig. 5 in Yokoyama et al., 2005). Also, this had significant edge contamination when using larger search radii. 


### Stuff that didn't work
1. Each time that a watershed is clipped from the DEM it is clipped and then reprojected. This seemed like a waste of effort and computational time since reprojecting has to be done every time so I tried to reproject the base DEM and then subset by watershed. This might have worked except that when reprojecting (at least with albers equal area) and changing the DEM resultion (from 4.9 to 5) it didn't keep exactly square cells. This wasn't much of a problem except that I kept getting an error that SAGA couldn't use DEMs with non-square cells (the cells were non-square at some ridiculous decimal precision as far as I could tell). In any case I finally decided to just reproject the subset DEM for each watershed. Oh well. 

Please also note that it is a good idea to reproject a DEM since slope doesn't seem to calculate right if the DEM is in geographic coordinate system. I chose to reproject to Albers Equal Area (EPSG: 102008) because I needed a projection that would cover the entire US when I apply this to the NED dataset and because this is the projection of the EDNA dataset. 

Here is the code that I learned while trying to fix this: 

If you need to set the projection info an a DEM use the following code to add the projection (which I knew) to the file
gdal_edit -a_srs EPSG:4326 NM_5m_dtm.tif

Reproject (took ~ 4 hours)
echo startTime: %time%
echo Now reprojecting DEM
gdalwarp -s_srs EPSG:4326 -t_srs EPSG:102008 -tr 5 5 -r bilinear -dstnodata -9999 c:\DEM\NM_5m_dtm.tif c:\DEM\NM_5m_dtm_p.tif
echo Finish Time: %time% 

This is what I used to reproject to 10 m.
echo startTime: %time%
echo Now reprojecting DEM to 10m
gdalwarp -tr 10 10 -r lanczos -dstnodata -9999 c:\DEM\NM_5m_dtm.tif c:\DEM\NM_10m_dtm.tif
echo Finish Time: %time% 


	
2. I also learned that it doesn't work to fill individual sub-watershed DEMs (HUC12) because the boundaries of these watersheds seem to be somewhat random and often fall in flat areas so that filling the DEM floods the DEM to the edges which no longer match up to the neighbor DEM. Filling larger extent watersheds (HUC8) does seem to work because the boundaries of these watersheds seem to correspond to actual hydrological divides in the landscape.  		
 
 
3. Multiple attempts using the following code to calculate Slope Height, Valley Depth, Normalized Height, Mid-slope position failed. However; I did get this to run via the gui so I don't know why the code doesn't work. In anycase, this took a fairly long time to run so I decided against calculating these derivatives. Still I think that they could be useful and should maybe be included in individual DSM projects, but will need to be run by watershed. 
 
REM REM Slope Height, Valley Depth, Normalized Height, Mid-slope position ##########
REM for %%i in (%tiles%) do (
 REM echo now calculating Slope Height of %fieldname% %%i 
  REM saga_cmd ta_morphometry 14 -DEM=%%i_sf.sgrd -HO=%%i_sh.sgrd -HU=%%i_vd.sgrd -NH=%%i_nh.sgrd -MS=%%i_ms.sgrd
   REM )
   
	REM for %%i in (%tiles%) do (
	 REM echo now trimming Slope Height of %fieldname% %%i
	  REM gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %BufferB% -crop_to_cutline -of GTiff %%i_sh.sdat %%i_sh.tif
	REM )   
	   
		REM for %%i in (%tiles%) do (	   
		 REM del %%i_sh.mgrd
		 REM del %%i_sh.prj
		 REM del %%i_sh.sdat
		 REM del %%i_sh.sdat.aux.xml
		 REM del %%i_sh.sgrd
		REM )

	REM for %%i in (%tiles%) do (
	 REM echo now trimming Valley Depth of %fieldname% %%i
	  REM gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %BufferB% -crop_to_cutline -of GTiff %%i_vd.sdat %%i_vd.tif
	REM )   
	   
		REM for %%i in (%tiles%) do (	   
		 REM del %%i_vd.mgrd
		 REM del %%i_vd.prj
		 REM del %%i_vd.sdat
		 REM del %%i_vd.sdat.aux.xml
		 REM del %%i_vd.sgrd
		REM )	
		
	REM for %%i in (%tiles%) do (
	 REM echo now trimming Normalized Height of %fieldname% %%i
	  REM gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %BufferB% -crop_to_cutline -of GTiff %%i_nh.sdat %%i_nh.tif
	REM )   
	   
		REM for %%i in (%tiles%) do (	   
		 REM del %%i_nh.mgrd
		 REM del %%i_nh.prj
		 REM del %%i_nh.sdat
		 REM del %%i_nh.sdat.aux.xml
		 REM del %%i_nh.sgrd
		REM )
		
	REM for %%i in (%tiles%) do (
	 REM echo now trimming Mid-slope position of %fieldname% %%i
	  REM gdalwarp -cutline %indexB% -cwhere "%fieldname% = '%%i'" -cblend %BufferB% -crop_to_cutline -of GTiff %%i_ms.sdat %%i_ms.tif
	REM )   
	   
		REM for %%i in (%tiles%) do (	   
		 REM del %%i_ms.mgrd
		 REM del %%i_ms.prj
		 REM del %%i_ms.sdat
		 REM del %%i_ms.sdat.aux.xml
		 REM del %%i_ms.sgrd
		REM ) 

## Authors

* **Colby Brungard, PhD**, Plant and Environmental Sciences Dept., New Mexico State University, Las Cruces, NM 88003, cbrung@nmsu.edu, +1-575-646-1907




