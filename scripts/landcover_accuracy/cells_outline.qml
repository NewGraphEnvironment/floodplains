<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<!-- The 10 m sample cell around each #93 point (#111): the square the label is about. Outline only, so
     the imagery under it stays readable; magenta because it is in no imagery palette.
     Labelled OUTSIDE the cell (placement 8, OutsidePolygons) with the Esri capture each
     "<year> Esri capture" theme shows there (#115): every capture_<year> column, e.g.
     "Esri 2017: 2017-06-11, 0.31 m". The cells layer is in every theme, so the label names Esri: it
     dates the Esri capture layer, not the Sentinel-2 or orthophoto under it. The expression reads the
     columns by prefix, so it needs no edit for an area with other endpoints. A layer with no capture
     columns draws no label. Read-only context: nothing of the design. -->
<qgis version="3.34.0" styleCategories="Symbology|Labeling" labelsEnabled="1">
 <renderer-v2 type="singleSymbol" symbollevels="0" enableorderby="0" forceraster="0" referencescale="-1">
  <symbols>
   <symbol type="fill" name="0" alpha="1" clip_to_extent="1" force_rhr="0">
    <layer class="SimpleLine" enabled="1" locked="0" pass="0">
     <Option type="Map">
      <Option value="255,0,255,255" name="line_color" type="QString"/>
      <Option value="solid" name="line_style" type="QString"/>
      <Option value="0.5" name="line_width" type="QString"/>
      <Option value="MM" name="line_width_unit" type="QString"/>
      <Option value="miter" name="joinstyle" type="QString"/>
     </Option>
    </layer>
   </symbol>
  </symbols>
 </renderer-v2>
 <labeling type="simple">
  <settings calloutType="simple">
   <text-style fieldName="array_to_string(array_foreach(array_filter(map_akeys(attributes()), left(@element, 8) = 'capture_'), 'Esri ' || substr(@element, 9) || ': ' || attribute(@element)), '&#xa;')" isExpression="1" fontSize="8" fontSizeUnit="Point" fontWeight="50" textColor="255,0,255,255" textOpacity="1">
    <text-buffer bufferDraw="1" bufferSize="0.8" bufferSizeUnits="MM" bufferColor="255,255,255,255" bufferOpacity="1"/>
   </text-style>
   <placement placement="8" dist="1" distUnits="MM"/>
   <rendering scaleVisibility="0" obstacle="1" fontLimitPixelSize="0"/>
  </settings>
 </labeling>
</qgis>
