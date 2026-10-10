# Modelled spawning and rearing by stream order, province (2026-10-10)

Share of modelled habitat length (km) on order-1, order-2 and order >= 3 FWA segments, per species and use, in the two habitat models in the local fwapg (`fresh-db`). For the #104 floor (floodplains#104, flooded#68 discussion). Run 2026-10-10 23:45 UTC on m1.

## bcfishpass: `fresh.streams_vw_bcfp` (188 watershed groups; habitat = codes 1, 2)

```
 sp  |  use  |  o1  |  o2  | o3plus |   km   
-----+-------+------+------+--------+--------
 bt  | rear  |  1.3 | 21.1 |   77.6 | 157657
 bt  | spawn |  0.7 | 12.1 |   87.2 |  91112
 ch  | rear  |  1.0 | 16.0 |   82.9 |  65585
 ch  | spawn |  0.6 |  5.2 |   94.2 |  48439
 cm  | spawn |  1.3 | 18.8 |   79.9 |  29651
 co  | rear  |  3.4 | 19.9 |   76.7 |  59690
 co  | spawn |  1.0 | 15.9 |   83.2 |  49905
 pk  | spawn |  0.9 | 17.8 |   81.3 |  32733
 sk  | rear  | 46.4 | 18.4 |   35.2 |  15624
 sk  | spawn |  0.9 |  7.6 |   91.5 |   2045
 st  | rear  |  1.3 | 19.2 |   79.5 |  54577
 st  | spawn |  0.8 |  6.1 |   93.1 |  34859
 wct | rear  |  1.4 | 10.7 |   87.9 |  15327
 wct | spawn |  0.9 |  7.1 |   92.0 |  12325
(14 rows)

```

## link: `fresh.streams` + `fresh.streams_habitat_<sp>` (98 watershed groups; habitat = TRUE; cm and pk have no rearing)

```
 sp  |  use  |  o1  |  o2  | o3plus |   km   
-----+-------+------+------+--------+--------
 bt  | rear  |  0.8 | 21.3 |   77.9 | 121731
 bt  | spawn |  0.7 | 12.3 |   87.0 |  73444
 ch  | rear  |  1.0 | 15.6 |   83.4 |  36401
 ch  | spawn |  0.8 |  5.3 |   93.9 |  27416
 cm  | spawn |  1.9 | 14.7 |   83.4 |  12540
 co  | rear  |  3.2 | 18.1 |   78.7 |  32708
 co  | spawn |  1.1 | 13.4 |   85.5 |  27186
 pk  | spawn |  1.0 | 14.6 |   84.4 |  15793
 sk  | rear  | 50.1 | 18.1 |   31.7 |   9706
 sk  | spawn |  1.2 |  8.2 |   90.6 |    996
 st  | rear  |  1.4 | 16.4 |   82.2 |  26339
 st  | spawn |  1.1 |  5.8 |   93.1 |  17575
 wct | rear  |  1.2 | 10.3 |   88.5 |   7688
 wct | spawn |  1.1 |  6.4 |   92.5 |   6265
(14 rows)

```

## Sockeye rearing on order 1 (bcfishpass): on a waterbody?

```
 on_waterbody |  km  
--------------+------
 t            | 7250
(1 row)

```

## Queries

bcfishpass, one row per species and use:

```sql
select '<sp>' sp, '<use>' use, round((100.0*sum(length_metre) filter (where stream_order=1)/nullif(sum(length_metre),0))::numeric,1) o1, round((100.0*sum(length_metre) filter (where stream_order=2)/nullif(sum(length_metre),0))::numeric,1) o2, round((100.0*sum(length_metre) filter (where stream_order>=3)/nullif(sum(length_metre),0))::numeric,1) o3plus, round((sum(length_metre)/1000)::numeric) km from fresh.streams_vw_bcfp where spawning|rearing_<sp> in (1,2)
```

link, one row per species and use:

```sql
select '<sp>' sp, '<use>' use, round((100.0*sum(s.length_metre) filter (where s.stream_order=1)/nullif(sum(s.length_metre),0))::numeric,1) o1, round((100.0*sum(s.length_metre) filter (where s.stream_order=2)/nullif(sum(s.length_metre),0))::numeric,1) o2, round((100.0*sum(s.length_metre) filter (where s.stream_order>=3)/nullif(sum(s.length_metre),0))::numeric,1) o3plus, round((sum(s.length_metre)/1000)::numeric) km from fresh.streams_habitat_<sp> h join fresh.streams s using (id_segment, watershed_group_code) where h.spawning|rearing
```

```sql
select (waterbody_key is not null) on_waterbody, round((sum(length_metre)/1000)::numeric) km from fresh.streams_vw_bcfp where rearing_sk in (1,2) and stream_order=1 group by 1
```
