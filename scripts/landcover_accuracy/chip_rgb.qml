<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<!-- True-colour rendering for the #93 reference chips (drift::dft_stac_composite, bands red/green/blue
     as surface reflectance, FLT4S). ONE fixed stretch, 0-0.25 reflectance on every band and every
     chip, so a brightness difference between two years is a real one -- a per-layer min/max stretch
     would equalise exactly the difference the reviewer is looking for. Added with stretch = "none"
     so rfp leaves this range alone. -->
<qgis version="3.34.0" styleCategories="Symbology">
 <pipe>
  <rasterrenderer type="multibandcolor" opacity="1" alphaBand="-1" redBand="1" greenBand="2" blueBand="3">
   <rasterTransparency/>
   <minMaxOrigin>
    <limits>None</limits>
    <extent>WholeRaster</extent>
    <statAccuracy>Estimated</statAccuracy>
    <cumulativeCutLower>0.02</cumulativeCutLower>
    <cumulativeCutUpper>0.98</cumulativeCutUpper>
    <stdDevFactor>2</stdDevFactor>
   </minMaxOrigin>
   <redContrastEnhancement>
    <minValue>0</minValue>
    <maxValue>0.25</maxValue>
    <algorithm>StretchToMinimumMaximum</algorithm>
   </redContrastEnhancement>
   <greenContrastEnhancement>
    <minValue>0</minValue>
    <maxValue>0.25</maxValue>
    <algorithm>StretchToMinimumMaximum</algorithm>
   </greenContrastEnhancement>
   <blueContrastEnhancement>
    <minValue>0</minValue>
    <maxValue>0.25</maxValue>
    <algorithm>StretchToMinimumMaximum</algorithm>
   </blueContrastEnhancement>
  </rasterrenderer>
  <brightnesscontrast brightness="0" contrast="0" gamma="1"/>
  <huesaturation saturation="0" grayscaleMode="0" colorizeOn="0"/>
  <rasterresampler maxOversample="2"/>
 </pipe>
 <blendMode>0</blendMode>
</qgis>
