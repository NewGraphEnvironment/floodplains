<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<!-- Reference-label form for the #93 accuracy sample (floodplains). Constrained values only:
     ref_from / ref_to store IO LULC class CODES (1 Water, 2 Trees, 4 Flooded Vegetation, 5 Crops,
     7 Built Area, 8 Bare Ground, 9 Snow/Ice, 11 Rangeland), because drift's estimator scores
     ref_from * 1000 + ref_to against the map's transition code. There is no "shrub" or "wetland"
     class: the reference is labelled in IO's legend or it cannot be compared with IO.
     "Cannot label" is a status, never a class.
     BLIND (#111): the layer carries no design column (no point_id, which encodes the stratum; no
     stratum; no IO map class), only an opaque review_id, the cell, the dated imagery covering the
     point, and the label fields. review_key.csv (committed, never shipped) maps the id back. Points are
     coloured by label progress and labelled with their review_id; work through them in id order. -->
<qgis version="3.34.0" styleCategories="Symbology|Labeling|Fields|Forms" labelsEnabled="1">
 <previewExpression>"review_id"</previewExpression>
 <renderer-v2 type="RuleRenderer" symbollevels="0" enableorderby="0" forceraster="0" referencescale="-1">
  <rules key="root">
   <rule key="todo" symbol="0" label="Not yet labelled" filter="&quot;label_status&quot; IS NULL OR &quot;label_status&quot; = ''"/>
   <rule key="done" symbol="1" label="Labelled" filter="&quot;label_status&quot; = 'labelled'"/>
   <rule key="cant" symbol="2" label="Cannot label" filter="&quot;label_status&quot; = 'cannot_label'"/>
  </rules>
  <symbols>
   <symbol type="marker" name="0" alpha="1" clip_to_extent="1" force_rhr="0">
    <layer class="SimpleMarker" enabled="1" locked="0" pass="0">
     <Option type="Map">
      <Option value="255,221,0,255" name="color" type="QString"/>
      <Option value="circle" name="name" type="QString"/>
      <Option value="0,0,0,255" name="outline_color" type="QString"/>
      <Option value="solid" name="outline_style" type="QString"/>
      <Option value="0.4" name="outline_width" type="QString"/>
      <Option value="MM" name="outline_width_unit" type="QString"/>
      <Option value="3" name="size" type="QString"/>
      <Option value="MM" name="size_unit" type="QString"/>
     </Option>
    </layer>
   </symbol>
   <symbol type="marker" name="1" alpha="1" clip_to_extent="1" force_rhr="0">
    <layer class="SimpleMarker" enabled="1" locked="0" pass="0">
     <Option type="Map">
      <Option value="51,160,44,255" name="color" type="QString"/>
      <Option value="circle" name="name" type="QString"/>
      <Option value="0,0,0,255" name="outline_color" type="QString"/>
      <Option value="solid" name="outline_style" type="QString"/>
      <Option value="0.4" name="outline_width" type="QString"/>
      <Option value="MM" name="outline_width_unit" type="QString"/>
      <Option value="2.4" name="size" type="QString"/>
      <Option value="MM" name="size_unit" type="QString"/>
     </Option>
    </layer>
   </symbol>
   <symbol type="marker" name="2" alpha="1" clip_to_extent="1" force_rhr="0">
    <layer class="SimpleMarker" enabled="1" locked="0" pass="0">
     <Option type="Map">
      <Option value="150,150,150,255" name="color" type="QString"/>
      <Option value="cross_fill" name="name" type="QString"/>
      <Option value="0,0,0,255" name="outline_color" type="QString"/>
      <Option value="solid" name="outline_style" type="QString"/>
      <Option value="0.4" name="outline_width" type="QString"/>
      <Option value="MM" name="outline_width_unit" type="QString"/>
      <Option value="2.4" name="size" type="QString"/>
      <Option value="MM" name="size_unit" type="QString"/>
     </Option>
    </layer>
   </symbol>
  </symbols>
 </renderer-v2>
 <labeling type="simple">
  <settings calloutType="simple">
   <text-style fieldName="review_id" isExpression="0" fontSize="9" fontSizeUnit="Point" fontWeight="75" textColor="0,0,0,255" textOpacity="1" namedStyle="Bold">
    <text-buffer bufferDraw="1" bufferSize="1" bufferSizeUnits="MM" bufferColor="255,255,255,255" bufferOpacity="1"/>
   </text-style>
   <placement placement="0" dist="1.5" distUnits="MM" quadOffset="2"/>
   <rendering scaleVisibility="0" obstacle="1" fontLimitPixelSize="0"/>
  </settings>
 </labeling>
 <fieldConfiguration>
  <field name="ref_from" configurationFlags="NoFlag">
  <editWidget type="ValueMap">
    <config>
      <Option type="Map">
        <Option name="map" type="List">
          <Option type="Map">
            <Option value="1" name="Water" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="2" name="Trees" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="4" name="Flooded Vegetation" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="5" name="Crops" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="7" name="Built Area" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="8" name="Bare Ground" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="9" name="Snow/Ice" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="11" name="Rangeland" type="QString"/>
          </Option>
        </Option>
      </Option>
    </config>
  </editWidget>
  </field>
  <field name="ref_to" configurationFlags="NoFlag">
  <editWidget type="ValueMap">
    <config>
      <Option type="Map">
        <Option name="map" type="List">
          <Option type="Map">
            <Option value="1" name="Water" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="2" name="Trees" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="4" name="Flooded Vegetation" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="5" name="Crops" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="7" name="Built Area" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="8" name="Bare Ground" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="9" name="Snow/Ice" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="11" name="Rangeland" type="QString"/>
          </Option>
        </Option>
      </Option>
    </config>
  </editWidget>
  </field>
  <field name="label_status" configurationFlags="NoFlag">
  <editWidget type="ValueMap">
    <config>
      <Option type="Map">
        <Option name="map" type="List">
          <Option type="Map">
            <Option value="labelled" name="Labelled" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="cannot_label" name="Cannot label (imagery insufficient)" type="QString"/>
          </Option>
        </Option>
      </Option>
    </config>
  </editWidget>
  </field>
  <field name="confidence" configurationFlags="NoFlag">
  <editWidget type="ValueMap">
    <config>
      <Option type="Map">
        <Option name="map" type="List">
          <Option type="Map">
            <Option value="high" name="High" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="medium" name="Medium" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="low" name="Low" type="QString"/>
          </Option>
        </Option>
      </Option>
    </config>
  </editWidget>
  </field>
  <field name="imagery" configurationFlags="NoFlag">
  <editWidget type="ValueMap">
    <config>
      <Option type="Map">
        <Option name="map" type="List">
          <Option type="Map">
            <Option value="s2_composite" name="Sentinel-2 dated composite" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="orthophoto" name="Orthophoto (dated)" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="airphoto" name="Air photo (dated)" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="esri" name="Esri basemap" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="google" name="Google basemap" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="bing" name="Bing basemap" type="QString"/>
          </Option>
          <Option type="Map">
            <Option value="several" name="Several together" type="QString"/>
          </Option>
        </Option>
      </Option>
    </config>
  </editWidget>
  </field>
  <field name="note" configurationFlags="NoFlag">
  <editWidget type="TextEdit">
    <config>
      <Option type="Map">
        <Option value="true" name="IsMultiline" type="bool"/>
        <Option value="false" name="UseHtml" type="bool"/>
      </Option>
    </config>
  </editWidget>
  </field>
  <field name="reviewer" configurationFlags="NoFlag">
  <editWidget type="TextEdit">
    <config>
      <Option type="Map">
        <Option value="false" name="IsMultiline" type="bool"/>
        <Option value="false" name="UseHtml" type="bool"/>
      </Option>
    </config>
  </editWidget>
  </field>
  <field name="labelled_on" configurationFlags="NoFlag">
  <editWidget type="DateTime">
    <config>
      <Option type="Map">
        <Option value="true" name="allow_null" type="bool"/>
        <Option value="true" name="calendar_popup" type="bool"/>
        <Option value="yyyy-MM-dd" name="display_format" type="QString"/>
        <Option value="yyyy-MM-dd" name="field_format" type="QString"/>
        <Option value="false" name="field_iso_format" type="bool"/>
      </Option>
    </config>
  </editWidget>
  </field>
 </fieldConfiguration>
 <aliases>
    <alias field="review_id" index="-1" name="Review id (work in this order)"/>
    <alias field="cell" index="-1" name="Sample cell"/>
    <alias field="dated_imagery" index="-1" name="Dated imagery covering this point"/>
    <alias field="ref_from" index="0" name="Reference class, first year"/>
    <alias field="ref_to" index="1" name="Reference class, last year"/>
    <alias field="label_status" index="2" name="Label status"/>
    <alias field="confidence" index="3" name="Confidence"/>
    <alias field="imagery" index="4" name="Imagery that settled it"/>
    <alias field="note" index="5" name="Note"/>
    <alias field="reviewer" index="6" name="Reviewer"/>
    <alias field="labelled_on" index="7" name="Labelled on"/>
 </aliases>
 <editable>
    <field name="review_id" editable="0"/>
    <field name="cell" editable="0"/>
    <field name="dated_imagery" editable="0"/>
    <field name="ref_from" editable="1"/>
    <field name="ref_to" editable="1"/>
    <field name="label_status" editable="1"/>
    <field name="confidence" editable="1"/>
    <field name="imagery" editable="1"/>
    <field name="note" editable="1"/>
    <field name="reviewer" editable="1"/>
    <field name="labelled_on" editable="1"/>
 </editable>
</qgis>
