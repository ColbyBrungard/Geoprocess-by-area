# Geoprocess DEMs by watershed

This project is for calculating many derivatives from a DEM for digital soil mapping.

This project takes a DEM as input then smooths and fills the DEM and derives a hillshade. The smoothed and filled DEM is then subset by (buffered) watershed and individual DEMs for each watershed are written to file. Multiple derivatives are then calculated for each watershed, the derivatives are trimmed back to 1/3 (e.g., 10 cells if the original buffer was 30 cells) the buffer distance to avoid edge contamination, and the trimmed derivatives are mosaicked back together by feathering over the 1/3 buffer distance. Intermediate processing data/files are deleted to save storage space. 

The reason that I took this approach is because I was running into memory issues when trying to calculate derivatives from a 5-m DEM over the state of New Mexico. To solve this I needed a way to tile the DEM in such a way that made physical sense and created hydrologically sound derivatives (I thought that square tiles would produce spurious flow routing values). 

## Getting Started

To run this code:  
1. install OSGeo4W available at: https://trac.osgeo.org/osgeo4w/ 
2. download the latest SagaGIS X binaries from: https://sourceforge.net/projects/saga-gis/files/ (this code tested with Saga 6.0.2_x64) 
3. download this file and save to the location where you have your DEM
4. open this batch file (I like Notepadd ++) and change the following (text inside parentheses is for annotation only and should not be included in your file):
	* set PATH=%PATH%;C:\saga-6.2.0_x64 (change the directory after the " %PATH%," to the location of where saga_cmd.exe is located)
	* SET SAGA_MLB=C:\saga-6.2.0_x64\tools (make sure the directory matches the directory above)

	* set WORK=c:\DEM (change to your working directory where your DEM and batch file are located)
	
	* set DEM=testDEM2.tif (name of DEM to calculate derivatives from)
	
	* set index=C:\DEM\testwatersheds_p2.shp (path to watershed shapefile. The shapefile and the DEM MUST be in the same projection). 
	
	* set fieldname=HUC12 (The column name of the shapefile attribute table with the watershed values) 
	
	* set buffer=30 (Set a buffer distance. This will be used when clipping the DEM by watershed. This distance will then be reduced by 2/3 (e.g., 30/3) and used to trim off edge effects of each derivative before feathering the edges over this distance (buffer/3) when mosaicking)
	
	* set tiles=130301030504 130301030505 130301030502 (The number of each polygon. Manually input a space separated vector of values for each polygon, these should be single values (not words) and contain NO spaces. This can easily be generated using the following R commands:
	
```
require(rgdal)
setwd("C:/DEM")
# Read SHAPEFILE.shp from the current working directory (".")
 shape <- readOGR(dsn = ".", layer = "testwatersheds_p2")
 shape@data$X
 # put the column name for X (e.g., HUC12)
 
```
5. review the list of derivatives (below), if there are some that you do not want, navigate to the code section that creates these derivatives (see in file comments), and block comment-out these sections (REM is the comment flag in .bat files)
	
6. open OSGeo4W, navigate to the folder where the .bat file is located (cd command), type the file name ( geoproces_by_area.bat), and hit enter.  

7.  let this run. it will take some time to process depending on the size of the input DEM. This took 3 hours 6 min to run for 3 huc 12 watersheds using a intel i-7 2.60 GHz processor and a 5-m DEM. 


### To DO: 
Put this into python so that I can parallelize the script. It currently runs on only one processor.
Use https://sourceforge.net/projects/saga-gis/files/SAGA%20-%20Documentation/Tutorials/Command_Line_Scripting/ as template for python integration. 
 
Note: I decided not to do this in R, because at the time I initiated this project, the RSAGA package no longer communicated with the latest versions of SAGA and the latest SAGA versions had several derivatives that were not available in SAGA 2.0X  	

### Prerequisites

OSGeo4W must be downloaded and installed, 
SAGA GIS binaries must be downloaded

### Covariate Names
The following covariates will be calculated from the input DEM

1. 	ELEV_SF Smoothed and filled DEM
2.	HSHADE Hillshade 
3.	C_GENE General Curvature
4.	C_PROF Profile Curvature
5.	C_PLAN Plan Curvature
6.	C_TANG Tangential Curvature
7.	C_LONG Longitudinal Curvature
8.	C_CROS Cross-Sectional Curvature
9.	C_MINI Minimal Curvature
10.	C_MAXI Maximal Curvature
11.	C_TOTA Total Curvature
12.	C_ROTO Flow Line Curvature
13.	DDG Downslope Distance gradient
14.	CI Convergence Index
15.	DAH Diurnal anisotropic heating
16.	TPI Multi-Scale Topographic Position Index
17.	MRVBF Multiresolution valley bottom flatness
18.	MRRTF Multiresolution ridge top flatness
19.	HO Slope height
20.	HU Valley depth
21.	NH Normalized height
22.	SH Standardized height
23.	MS Mid-Slope position
24.	TRI Terrain Ruggedness Index
25.	TSCv Terrain Surface Convexity
26.	TSCc Terrain Surface Concavity 
27.	CL Local curvature
28.	CUP Upslope Curvature
29.	CD Downslope Curvature 
30.	CAR Catchment Area
31.	CSL Catchment Slope
32.	MCA Modified Catchment Area
33.	SWI Saga Wetness Index 
34.	PO Positive openness
35.	NO Negative openness


### Settings and thoughts on saga modules that were used.

A. Smoothing: 3x3 (circle with radius of 2 cells) smoothing filter

B. Sink Filling: Wang & Liu with min slope value of 0.1 degree (the default). This preserves a downslope flow when filling. 

C. Analytical hillshade: Azimuth = 315, declination = 45

D. Slope, general, profile, plan, tangential, longitudinal, cross, minimum, maximum, total, and flow line curvature all calculated using the Zevenbergen and Thorne 1987 method. Slope is in percent. 

E. Convergence index: neighbors = 3x3, method = gradient. "The index is obtained by averaging the bias of the slope directions of the adjacent calls from the direction of the central cell, and subtracting 90 degrees. The possible values of the index range from -90 to +90 degrees. Values for a cell where all eight neighbors drain to the cell (pit) are -90, values for a cell where all eight neighbors drain away from the cell center (peak) is 90, values for a cell where all eight neighbors drain to one direction are 0." From: Kiss, R (2004). Determination of drainage network in digital elevation models, utilities and limitations, Journal of Hungarian Geomathematics, 2, 16-29.)

F. Diurnal Anisotropic Heating. The angle is set to 225 with is a southwest angle.
 
G. Downslope Distance Gradient - how far downslope does one have to go to descend d meters?, http://onlinelibrary.wiley.com/doi/10.1029/2004WR003130/full. This maybe useful for modeling soil depth, probably in humid environments.d (distance) is set to = 5 since this is the resolution of the DEM. That seems logical to me. Output is gradient in degrees, but by modifying the -OUTPUT argurment it could also be distance. 

H. MultiScale Topographic Position Index. Default parameters (scale_min, scale_Max, scale_num) seemed good to me.

I. MRVBF http://onlinelibrary.wiley.com/doi/10.1029/2002WR001426/abstract. Intended for separating erosional and depositional areas. Valley bottoms = depositional areas. MRVBF: higher values indicate that this is more likely a valley bottom. MRRTF: higher values indicate more likely a ridge. "While MRVBF is a continuous measure, it naturally divides into classes corresponding to the different resolutions and slope thresholds. Values less than 0.5 are not valley bottom areas. Values from 0.5 to 1.5 are considered to be the steepest and smallest resolvable valley bottoms for 25 m DEMs. Flatter and larger valley bottoms are represented by values from 1.5 to 2.5, 2.5 to 3.5, and so on" . According to the paper, T_Slope was set to 44. This was chosen by fitting a power relationship between the resolution and the thresholds listed in paragraph 26 in the paper (the equation is y (t_slope) = 1659.51*(DEM resolution ^-0.819). All other parameters were left to default values as suggested by the paper (section 2.8). You probably want to change this default value for the resolution of your DEM. You can do this by using the above equation, then searching the code for T_Slope and modifying this value in the code. That said, I didn't find much of a difference between the default settings in flat terrain.  

J. Relative heights and slope positions. Didn't see much reason to change the default settings (W=0.5, T=10, E=2)

K. Terrain Ruggedness Index. Which areas are the most rugged. "Calculates the sum change in elevation between a grid cell and its eight neighbor grid cells. I chose a radius of 10 cells (so for a 5 m DEM, 10x5 = 50m (or 100 m diameter)), and a circular mode. https://www.researchgate.net/publication/259011943_A_Terrain_Ruggedness_Index_that_Quantifies_Topographic_Heterogeneity 

L. Terrain Surface Convexity. Had to take the defaults since I couldn't get access to the paper. Probably a bad idea. Kernel 1 = eight neighborhood 

N. Upslope and downslope curvature. https://www.sciencedirect.com/science/article/pii/009830049190048I. Decided against using up and down local curvature since they weren't very different than up/down curvature. 

O. Saga wetness index. Kept defaults as is. Catchment slope is suspect, but I was testing in relatively flat terrain. 

P. Topographic Openness- I'm not sure this makes much sense in an arid environment, but since it was intended to be input for geomorphological mapping I thought it might be interesting. 


### Thoughts on saga modules that I didn't use. 

A. Morphometric Protection Index took a long time to run and then never produced a result. I'm also not sure what it would be good for. Maybe detecting sinkholes? 
 
B. Mass balance index would be cool but I need a few other parameters. http://onlinelibrary.wiley.com/doi/10.1002/jpln.200625039/pdf  
 
C. Use ta_morphometry 23 to calculate standard derivatives (slope, etc.) using larger cell sizes.

D. I want to use the Wind Effect (Windward/Leeward Index) as I think it may be useful as a predictor, but I think that I need to use a grid of wind directions. Can I get Josue to pull wind data from all weather stations, then interpolate? 
 
E. I decided against calculating the vector ruggedness measure (https://onlinelibrary.wiley.com/doi/epdf/10.2193/2005-723), because the intent of this algorithm is to quantify landscape ruggedness for species (big horn sheep) modeling and this didn't seem relevant to soil development.
 
F. Wind Exposition Index (https://www.earth-syst-dynam.net/6/61/2015/esd-6-61-2015.pdf) this seems more intended for rain shadow effects and climate downscaling than digital soil mapping and I decided against it. However; it probably has some predictive power for large scale modeling. I did run it in the GUI (it takes ~ 30 min for a HUC 12 watershed) and I don't see much utility in it.  

G. SaLEM model is meant for escarpment modeling of initially flat terrain. I suppose that this might work for valley borders along the Rio Grande, but maybe not useful since I'm not dealing with bedrock, but deposited sediment. 

H. Compound analysis Useful for Channel Network Base level, channels, relative slope position, but it is broken. Tried commandline and gui and it just hung up. 

I. Vertical Distance to Channel Network - requires channel network, which I can probably get from ta_compound 0, but which may give me relative elevation

J. Terrain surface texture. Defaults parameters (epsilon=1, scale=10, method=1, DW_weighting=3, DW_bandwith=0.7) only produced non-sensible results (circles of high values), but I don't know how exactly what the parameters should be changed to. 


## Authors

* **Colby Brungard, PhD**, Plant and Environmental Sciences Dept., New Mexico State University, Las Cruces, NM 88003, cbrung@nmsu.edu, +1-575-646-1907




