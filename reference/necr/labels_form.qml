<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<!-- Reference-label form for the #93 accuracy sample (floodplains). Constrained values only:
     ref_from / ref_to store IO LULC class CODES (1 Water, 2 Trees, 4 Flooded Vegetation, 5 Crops,
     7 Built Area, 8 Bare Ground, 9 Snow/Ice, 11 Rangeland), because drift's estimator scores
     ref_from * 1000 + ref_to against the map's transition code. There is no "shrub" or "wetland"
     class: the reference is labelled in IO's legend or it cannot be compared with IO.
     "Cannot label" is a status, never a class. The map fields are read-only. -->
<qgis version="3.34.0" styleCategories="Fields|Forms">
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
    <field name="point_id" editable="0"/>
    <field name="stratum" editable="0"/>
    <field name="stratum_label" editable="0"/>
    <field name="map_class" editable="0"/>
    <field name="map_2017" editable="0"/>
    <field name="map_2018" editable="0"/>
    <field name="map_2019" editable="0"/>
    <field name="map_2020" editable="0"/>
    <field name="map_2021" editable="0"/>
    <field name="map_2022" editable="0"/>
    <field name="map_2023" editable="0"/>
    <field name="in_fire_poly" editable="0"/>
    <field name="in_harvest_poly" editable="0"/>
    <field name="in_fwa_wetland" editable="0"/>
    <field name="use" editable="0"/>
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
