# Geoprocess DEM by watershed

This project is for calculating many derivatives from a DEM for digital soil mapping.

This project takes a DEM as input then smooths and fills the DEM and derives a hillshade. The smoothed and filled DEM is then subset by (buffered) watershed and individual DEMs for each watershed are written to file. Multiple derivatives are then calculated for each watershed, the derivatives are trimmed back to 1/3 (e.g., 10 cells if the original buffer was 30 cells) the buffer distance to avoid edge contamination, and the trimmed derivatives are mosaiced back together by feathering over the 1/3 buffer distance. 

The reason that I took this approach is because I was running into memory issues when trying to calculate derivatives from a 5-m DEM over the state of New Mexico. To solve this I needed a way to tile the DEM in such a way that made physical sense and created hydrologically sound derivatives (I thought that square tiles would produce spurious flow routing values). This entire process probably takes much longer than just running the algorithms on the original DEM, but I also wanted to figure out since I think I would like to use a similar approach to modeling different geomorphic environments.

## Getting Started

To run this code:  
1. install OSGeo4W available at: https://trac.osgeo.org/osgeo4w/ 
2. download the latest SagaGIS X binaries? from: https://sourceforge.net/projects/saga-gis/files/ (this code tested with Saga 6.0.2_x64) 
3. download this file and save to the location where you have your DEM
4. open this batch file (I like Notepadd ++) and change the following (text inside parentheses is for annotation only and should not be included in your file):
	* set PATH=%PATH%;C:\saga-6.2.0_x64 (change the directory after the " %PATH%," to the location of where saga_cmd.exe is located)
	* SET SAGA_MLB=C:\saga-6.2.0_x64\tools (make sure the directory matches the directory above)

	* set WORK=c:\DEM (change to your working directory where your DEM and batch file are located)
	
	* set DEM=testDEM2.tif (name of DEM to calculate derivatives from)
	
	* set index=C:\DEM\testwatersheds_p2.shp (path to watershed shapefile. The shapefile and the dem MUST be in the same projection). 
	
	* set tiles=130301030504 130301030505 130301030502 (The number of each polygon. Manually input a space separated vector of values for each polygon, these should be single values (not words) and contain NO spaces. 
	
	* set fieldname=HUC12 (The column name of the shapefile attribute table with the watershed values) 
	
	* set buffer=30 (Set a buffer distance. This will be used when clipping the DEM by watershed. This distance will then be reduced by 2/3 (e.g., 30/3) and used to trim off edge effects of each derivative before feathering the edges over this distance (buffer/3) when mosaicing)
	
4) open OSGeo4W, navigate to the folder where this file is located (cd command), type the file name (e.g., geoprocessing.bat). 

5) let this run. it will take some time to process depending on the size of the input DEM. This took 3 hours 6 min to run for 3 huc 12 watersheds using a intel i-7 2.60 GHz processor and a 5-m DEM. I need to put this into python to parallize	

### Prerequisites

OSGeo4W must be downloaded and installed
SAGA GIS binaries must be downloaded

```
Give examples
```

### Covariate Names
The following covariates will be calculated from the input DEM

ELEV_SF Smoothed and filled DEM
HSHADE Hillshade 
C_GENE General Curvature
C_PROF Profile Curvature
C_PLAN Plan Curvature
C_TANG Tangential Curvature
C_LONG Longitudinal Curvature
C_CROS Cross-Sectional Curvature
C_MINI Minimal Curvature
C_MAXI Maximal Curvature
C_TOTA Total Curvature
C_ROTO Flow Line Curvature
DDG Downslope Distance gradient
CI Convergence Index
DAH Diurnal anisotropic heating
TPI Multi-Scale Topographic Position Index
MRVBF Multiresolution valley bottom flatness
MRRTF Multiresolution ridge top flatness
HO Slope height
HU Valley depth
NH Normalized height
SH Standardized height
MS Mid-Slope position
TRI Terrain Ruggedness Index
TSCv Terrain Surface Convexity
TSCc Terrain Surface Concavity 
CL Local curvature
CUP Upslope Curvature
CD Downslope Curvature 
CAR Catchment Area
CSL Catchment Slope
MCA Modified Catchment Area
SWI Saga Wetness Index 
PO Positive openness
NO Negative openness


## Running the tests

Explain how to run the automated tests for this system

### Break down into end to end tests

Explain what these tests test and why

```
Give an example
```

### And coding style tests

Explain what these tests test and why

```
Give an example
```

## Deployment

Add additional notes about how to deploy this on a live system

## Built With

* [Dropwizard](http://www.dropwizard.io/1.0.2/docs/) - The web framework used
* [Maven](https://maven.apache.org/) - Dependency Management
* [ROME](https://rometools.github.io/rome/) - Used to generate RSS Feeds

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/your/project/tags). 

## Authors

* **Billie Thompson** - *Initial work* - [PurpleBooth](https://github.com/PurpleBooth)

See also the list of [contributors](https://github.com/your/project/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* Hat tip to anyone who's code was used
* Inspiration
* etc

