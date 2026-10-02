<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<!-- True-colour rendering for the dated high-resolution reference layers (#103): orthophotos and
     georeferenced digital air photos, both 8-bit RGB. Fixed 0-255 on every band, so the image shows as
     its producer encoded it and two epochs compare honestly; a per-layer min/max stretch would equalise
     the very difference the reviewer is looking for. Added with stretch = "none" so rfp leaves it.
     THIS copy reads band 4 as alpha: fly_georef writes RGBA, masking the frame border, which would
     otherwise draw as an opaque black edge over the neighbouring frame. dated_rgb.qml (no alpha) is
     for the 3-band orthophotos. -->
<qgis version="3.34.0" styleCategories="Symbology">
 <pipe>
  <rasterrenderer type="multibandcolor" opacity="1" alphaBand="4" redBand="1" greenBand="2" blueBand="3">
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
    <maxValue>255</maxValue>
    <algorithm>StretchToMinimumMaximum</algorithm>
   </redContrastEnhancement>
   <greenContrastEnhancement>
    <minValue>0</minValue>
    <maxValue>255</maxValue>
    <algorithm>StretchToMinimumMaximum</algorithm>
   </greenContrastEnhancement>
   <blueContrastEnhancement>
    <minValue>0</minValue>
    <maxValue>255</maxValue>
    <algorithm>StretchToMinimumMaximum</algorithm>
   </blueContrastEnhancement>
  </rasterrenderer>
  <brightnesscontrast brightness="0" contrast="0" gamma="1"/>
  <huesaturation saturation="0" grayscaleMode="0" colorizeOn="0"/>
  <rasterresampler maxOversample="2"/>
 </pipe>
 <blendMode>0</blendMode>
</qgis>
