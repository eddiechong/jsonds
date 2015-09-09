/*--==========================================================================
This is the Postgres Stored Proc that generates the JSON format for
a normal DS API call

Parameters: SID
Returns: JSON formatted DataSource specs for a single SKU
==========================================================================--*/

CREATE OR REPLACE FUNCTION dsjson (pid character varying(40))
RETURNS json AS $$

DECLARE
	v_std json;
	v_main json;
	v_extd json;

	v_imgs json;
	v_mktd json;
	v_kspt json;
	v_witb json;
	v_pfts json;
	
	v_total json;
	v_start_time timestamp := now();
Begin
	raise notice 'starting process ... %', v_start_time;

	Begin
		--building digital content
		with tmp_dc as (
			select dcmv3.metaValueName as imageid, dc.contentguid, dc.url, cast(dcmv.metaValueName as int) as width, cast(dcmv1.metaValueName as int) as height, cast(dcmv2.metaValueName as int) as image_weigth
			FROM   cds_digcontent dc
			inner join cds_digcontent_links dl on dc.contentguid = dl.contentguid
			-- width
			join cds_digContent_meta dcm on dcm.contentGuid = dc.contentGuid and dcm.metaAtrId = 3
			join cds_digContent_meta_valVoc dcmv on dcmv.metaValueId = dcm.metaValueId
			-- heigth
			join cds_digContent_meta dcm1 on dcm1.contentGuid = dc.contentGuid and dcm1.metaAtrId = 4
			join cds_digContent_meta_valVoc dcmv1 on dcmv1.metaValueId = dcm1.metaValueId
			-- image weight
			join cds_digContent_meta dcm2 on dcm2.contentGuid = dc.contentGuid and dcm2.metaAtrId = 7
			join cds_digContent_meta_valVoc dcmv2 on dcmv2.metaValueId = dcm2.metaValueId
			-- image id
			join cds_digContent_meta dcm3 on dcm3.contentGuid = dc.contentGuid and dcm3.metaAtrId = 8
			join cds_digContent_meta_valVoc dcmv3 on dcmv3.metaValueId = dcm3.metaValueId
			where dl.prodid = pid and dc.mediaTypeId = 15 
			order by image_weigth desc, width desc
			)
		select json_agg(x) into v_imgs
		from 
			(select d.url as full, d.width as w, d.height as h, s.url as s200, p.url as p75
			from tmp_dc d
			inner join 
				(select imageid, max(width) as max_width from tmp_dc group by imageid) m on (d.imageid = m.imageid and d.width = m.max_width)
			inner join 
				(select imageid, url from tmp_dc where width = 75) p on (d.imageid = p.imageid)
			inner join 
				(select imageid, url from tmp_dc where width = 200) s on (d.imageid = s.imageid)) x;
	End;
	

	Begin
		--building marketing text
		select json_build_object('ccs-marketing-text', 
			json_build_object('mkt', 
			json_build_object('name', 'Marketing Text', 
			'lines', json_agg(dat)))) into v_mktd
		from
			(SELECT cast(unnest(xpath('/body/text()', content)) as text) as dat
			FROM   cds_digcontent_data c
			inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
			where prodid = pid and mediatypeid = 4) k;
	End;

	Begin
		--building key selling point
		select json_build_object('ccs-ksp-features', 
			json_build_object('ksp', 
				json_build_object('name', 'Key Selling Points', 
				'lines', json_agg(dat)))) into v_kspt
		from
			(SELECT cast(unnest(xpath('/body/ul/li/text()', content)) as text) as dat
			FROM   cds_digcontent_data c
			inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
			where l.prodid= pid and mediatypeid = 5) k;
	End;

	Begin
		--building what's in the box
		select json_build_object('ccs-whats-in-the-box', 
			json_build_object('wib', 
				json_build_object('name', 'Whats in the Box', 
				'lines', json_agg(dat)))) into v_witb
		from
			(SELECT cast(unnest(xpath('/body/ul/li/text()', content)) as text) as dat
			FROM   cds_digcontent_data c
			inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
			where prodid= pid  and mediatypeid = 10) k;
	End;
		
	Begin
		--building product features
		select json_build_object('ccs-product-features', 
			json_build_object('pft', 
				json_build_object('name', 'Product Features', 
				'lines', json_agg(dat)))) into v_pfts
		from
			(SELECT cast(unnest(xpath('/body/ul/li/strong/text()', content)) as text) as dat
			FROM   cds_digcontent_data c
			inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
			where l.prodid= pid and mediatypeid = 14) k;
	End;

	Begin
		--building specs
		select json_build_object('ccs-standard-desc', description, 'ccs-product-name', description) into v_std
		from cds_stdnez 
		where ProdID = pid;

		--raise notice 'std descr ... %', v_std;
		
	End;

	Begin
		--building main specs
		select json_build_object('ccs-main-spec',
			json_build_object('items', array_to_json(array_agg(row_to_json(ms))))) into v_main
		from 
			(select v.text as name,  v2.text as lines
			from cds_Mspecez m
			join cds_Mvocez v on m.HdrID = v.ID 
			join cds_Mvocez v2 on m.BodyID = v2.ID
			where m.ProdID = pid
			order by m.ProdID, m.DisplayOrder) ms;

		--raise notice 'main specs ... %', v_main;		
	End;


	Begin
		--extended specs
		select json_build_object('ccs-ext-spec',
			json_build_object('blocks', 
				array_to_json(array_agg(row_to_json(gp))))) into v_extd
		from
			(select head, json_agg(items) as items
			from 
				(select v.text as head, json_build_object('name', v2.text, 'lines', v3.text) as items
				from cds_Especez e
				join cds_Evocez v on e.SectID = v.ID
				join cds_Evocez v2 on e.HdrID = v2.ID
				join cds_Evocez v3 on e.BodyID = v3.ID
				where e.ProdID = pid) es
			group by head) gp;

		--raise notice 'ext specs ... %', v_extd;
	End;
	
	--note: should only add them if not empty ...

	select json_append(v_total, json_build_object('ccs-tiled-gallery', json_build_object('images', v_imgs))) into v_total;

	select json_append(v_total, json_build_object('ccs-gallery', json_build_object('images', v_imgs))) into v_total;

	with v_stdimg as (select json_array_elements(v_imgs) limit 1)
	select json_append(v_total, json_build_object('ccs-standard-image', v_stdimg)) into v_total;
	
	select json_append(v_total, v_std) into v_total;
	
	select json_append(v_total, v_mktd) into v_total;
	select json_append(v_total, v_kspt) into v_total;
	select json_append(v_total, v_pfts) into v_total;
	select json_append(v_total, v_witb) into v_total;
	
	select json_append(v_total, v_main) into v_total;
	select json_append(v_total, v_extd) into v_total;
	
	return v_total;
End;
$$ LANGUAGE plpgsql;
 
select dsjson('S6458630');
select dsjson('S11328480');

select from wallmart.cds_digcontent_data

/*--========================================================================
1;"Standard Image (200x150)"
2;"CNET Medium Image (400x300)"
4;"Marketing description"
5;"Key Selling Points"
10;"What's in the Box"
11;"Product Data Sheet / Brochure"
12;"User Manual"
13;"Quick Start Guide"
14;"Product Features"
15;"CCS Product Image"
========================================================================--*/
--all XML contents, 4,5,10,14
select * from cds_digcontent_media_types

select json_build_object('ccs-ksp-features', 
	json_build_object('ksp', 
		json_build_object('name', 'Key Selling Points', 
		'lines', json_agg(ksp))))
	from
		(SELECT cast(unnest(xpath('/body/ul/li/text()', content)) as text) as ksp
		FROM   cds_digcontent_data c
		inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
		where prodid= 'S6458630' and mediatypeid = 5) k


--we only want english 
delete from cds_digcontent_data where contentguid in
(select d.contentguid from cds_digcontent_data d inner join cds_digcontent_lang_links l on d.contentguid = lower(l.contentguid) where languagecode <> 'en')

select * from cds_digcontent_lang_links where languagecode = 'Inv' limit 100;

select json_build_object('ccs-ksp-features',
	json_build_object('features', 
		json_build_object('head', 'Product Features',
		'items', json_agg(ft))))
from
	(select json_build_object('name', nm, 'lines', ln) as ft
	from
		(SELECT unnest(xpath('/body/ul/li/strong/text()', content)) as nm, 
			unnest(xpath('/body/ul/li/text()', content)) as ln
		FROM   cds_digcontent_data c
		inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
		where l.prodid= 'S11328480' and mediatypeid = 14) x) y






'With a blazing-fast Intel Core i5 processor, the Samsung ATIV Smart PC Pro 700T runs the same programs as your desktop PC in a sleek, light and compact form. A fast and simple touch screen interface lets you access all your favorite programs and apps with ease. Because when you combine power and design, amazing things happen. Welcome to the Samsung ATIV Smart PC Pro 700T.'

<body><ul>
<li><strong>
	<![CDATA[It may look like a tablet, but the Samsung ATIV Smart PC Pro 700T packs a powerful PC punch]]></strong><br /><![CDATA[With a blazing-fast Intel Core i5 processor, the Samsung ATIV Smart PC Pro 700T runs the same programs as your desktop PC in a sleek, light and compact form. A fast and simple touch screen interface lets you access all your favorite programs and apps with ease. Because when you combine power and design, amazing things happen. Welcome to the Samsung ATIV Smart PC Pro 700T.]]></li>
<li><strong><![CDATA[Use the simple touch screen interface to explore your favorite programs]]></strong><br /><![CDATA[The Samsung ATIV Smart PC Pro 700T is so easy and natural to use, it'll make you want to rediscover the PC experience.]]></li>
<li><strong><![CDATA[Share apps and content across devices with the touch of a finger]]></strong><br /><![CDATA[Now you can connect your Samsung ATIV Smart PC Pro 700T with multiple compatible devices via the Internet. Use S manager to update and to download AllShare technology to share content with a Samsung Smart TV, smartphone or camera, stream music, movies and photos from your Samsung ATIV Smart PC Pro 700T to your Smart TV.]]></li>
</ul></body>'


regexp_split_to_array('', pattern text [, flags text ])




SELECT *
FROM   cds_digcontent_data c
inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
where prodid= 'S9537017'
where l.contentguid = '125501BF-36F7-4627-A4D9-0019DB92D5A1'

select * from cds_digcontent_links where contentguid = '125501BF-36F7-4627-A4D9-0019DB92D5A1'
select * from cds_digcontent where contentguid = '125501BF-36F7-4627-A4D9-0019DB92D5A1'
select * from cds_digcontent_data where mediatypeid = 14 limit 10 
select * from cds_digcontent_links where contentguid = UPPER('28b233ed-6bdc-4638-8793-22195412a6e5')

--need to filter out en only 
select distinct(languagecode) from cds_digcontent_lang_links
select * from cds_digcontent_lang_links where languagecode = 'Inv' limit 100

delete from cds_digcontent_data where contentguid in
	(select distinct d.contentguid
	from cds_digcontent_data d 
	inner join cds_digcontent_lang_links l on d.contentguid = lower(l.contentguid)
	where l.languagecode <> 'en');

select * from cds_digcontent_data limit 10;
select * from cds_digcontent_links where prodid= 'S6458630'
select * from cds_digcontent_data where contentguid = lower('B448F01F-5901-48EF-A296-83608E2353A2')
select count(*) from cds_digcontent_data 

--grab for a given prodid
select distinct c.contentguid, c.mediatypeid, replace(c.url, 'http://cdn.cnetcontent.com', '') as url
from cds_digcontent c
inner join cds_digcontent_links l on c.contentguid = l.contentguid
where c.mediatypeid in (4,5,10,14) and prodid = 'S6458630';


--all XML content ... almost 31K of XMLs to download / process !!! arggghhh
select distinct c.contentguid, c.mediatypeid, replace(c.url, 'http://cdn.cnetcontent.com', '') as url
from cds_digcontent c
inner join cds_digcontent_links l on c.contentguid = l.contentguid
where c.mediatypeid in (4,5,10,14)
limit 100;

--not supposed to grab all languages, only english !

--========================================================================================
-- this will generate the SQL to download XMLs & also to reimport the data back into tables
-- \o output.sql          			- will set the output
-- \pset tuples_only       			- this will turn off header & footer
-- psql -U postgres -W -d datasample_us   	- this will login using psql & force prompt for passwd
--========================================================================================
--run this to download all the indivisual XMLs
select distinct 'wget ' || c.url from cds_digcontent c inner join cds_digcontent_links l on c.contentguid = l.contentguid where c.mediatypeid in (4,5,10,14);

select count(*) from cds_digcontent c inner join cds_digcontent_links l on c.contentguid = l.contentguid where c.mediatypeid in (4,5,10,14);

--this is the SQL to generate update.sql ========================================================================================
select distinct 'insert into cds_digcontent_data (contentguid, mediatypeid, content) values  (''' || lower(c.contentguid) || ''',' 
|| c.mediatypeid || ',' || 'convert_from(bytea_import(''/home/eddiec/Dev/jsonds/data/' || lower(c.contentguid) || '.xml''), ''utf8'')::xml);'
from cds_digcontent c
where c.mediatypeid in (4,5,10,14);



insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('a536453e-941c-478a-809a-80d2fa2b56b3',4,convert_from(bytea_import('/home/eddiec/Dev/jsonds/data/a536453e-941c-478a-809a-80d2fa2b56b3.xml'), 'utf8')::xml);


insert into cds_ksp (prodid, contentguid, ksp) values  ('42464211', '1cc31c53-128b-4f40-a018-4a1b989d0673', 'xml')

insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('42464211', '1cc31c53-128b-4f40-a018-4a1b989d0673', '`cat //tmp/ksp/1cc31c53-128b-4f40-a018-4a1b989d0673.xml`');

truncate table cds_digcontent_data
select * from cds_digcontent_data

SHOW  data_directory;

select pg_read_file('/home/eddiec/Dev/jsonds/data/c0a058ad-ca18-42ac-a2b4-17721b2ad1d1.xml', 0, 10000)


insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('61d1e814-6456-4166-8cf1-fe286c42c8b1',10,convert_from(bytea_import('/home/eddiec/Dev/jsonds/data/61d1e814-6456-4166-8cf1-fe286c42c8b1.xml'), 'utf8')::xml);


select * from cds_digcontent_data limit 100;
select count(*), mediatypeid from cds_digcontent_data group by mediatypeid;

/*--========================================================================================
-- Digital Content (Images_
2;'en';'Image Type'
3;'en';'Image Width'
4;'en';'Image Height'
5;'en';'File Size'
6;'en';'Resolution'
7;'en';'Image Weight' ***
8;'en';'Image ID'
9;'en';'Copyright'
10;'en';'Clipping Path'
========================================================================================--*/



select *
from cds_DigContent_Meta_AtrVoc
order by metaAtrID



--business logic for cloud is:
-- for each unique image id, grab maximum image resolution
-- then always gets the 200x150 & 75x75 image

--==================================================================================================================================

--unfolding dc is a bitch !

--==================================================================================================================================



		with tmp_dc as (
			select dcmv3.metaValueName as imageid, dc.contentguid, dc.url, cast(dcmv.metaValueName as int) as width, cast(dcmv1.metaValueName as int) as height, cast(dcmv2.metaValueName as int) as image_weigth
			FROM   cds_digcontent dc
			inner join cds_digcontent_links dl on dc.contentguid = dl.contentguid
			-- width
			join cds_digContent_meta dcm on dcm.contentGuid = dc.contentGuid and dcm.metaAtrId = 3
			join cds_digContent_meta_valVoc dcmv on dcmv.metaValueId = dcm.metaValueId
			-- heigth
			join cds_digContent_meta dcm1 on dcm1.contentGuid = dc.contentGuid and dcm1.metaAtrId = 4
			join cds_digContent_meta_valVoc dcmv1 on dcmv1.metaValueId = dcm1.metaValueId
			-- image weight
			join cds_digContent_meta dcm2 on dcm2.contentGuid = dc.contentGuid and dcm2.metaAtrId = 7
			join cds_digContent_meta_valVoc dcmv2 on dcmv2.metaValueId = dcm2.metaValueId
			-- image id
			join cds_digContent_meta dcm3 on dcm3.contentGuid = dc.contentGuid and dcm3.metaAtrId = 8
			join cds_digContent_meta_valVoc dcmv3 on dcmv3.metaValueId = dcm3.metaValueId
			where dl.prodid = 'S11328480' and dc.mediaTypeId = 15 
			order by image_weigth desc, width desc
			)
		select (json_array_elements(json_agg(x)))
		--select json_build_object('images', json_agg(x))
		from 
			(select d.url as full, d.width as w, d.height as h, s.url as s200, p.url as p75
			from tmp_dc d
			inner join 
				(select imageid, max(width) as max_width from tmp_dc group by imageid) m on (d.imageid = m.imageid and d.width = m.max_width)
			inner join 
				(select imageid, url from tmp_dc where width = 75) p on (d.imageid = p.imageid)
			inner join 
				(select imageid, url from tmp_dc where width = 200) s on (d.imageid = s.imageid)) x
				limit 1;



		--building marketing text
		select json_build_object('ccs-marketing-text', 
			json_build_object('mkt', 
			json_build_object('name', 'Marketing Text', 
			'lines', json_agg(dat)))) 
		from
			(SELECT cast(unnest(xpath('/body/text()', content)) as text) as dat
			FROM   cds_digcontent_data c
			inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
			where prodid = 'S11328480' and mediatypeid = 4) k;

select * from cds_digcontent_data limit 10; where 

--==================================================================================================================================


select *
FROM   cds_digcontent_data c
inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
where l.prodid = 'S11328480' and c.mediaTypeId = 14
	




--need the API to look like this !
-- http://ws.cnetcontent.com/e86c3b7c/api/1fc9b350fd?cpn=S10841413&lang=en



--==================================================================================================================================

select json_build_object('ccs-ksp-features', 
	json_build_object('ksp', 
		json_build_object('name', 'Key Selling Points', 
		'lines', json_agg(ksp))))

select json_object_agg(imageid, width)
from
	(select dc.contentGuid, dc.url,
		dcmv.metaValueName as width,
		dcmv1.metaValueName as heigth,
		dcmv2.metaValueName as imageid
	FROM   cds_digcontent dc
	inner join cds_digcontent_links dl on dc.contentguid = dl.contentguid
	-- width
	join cds_digContent_meta dcm on dcm.contentGuid = dc.contentGuid and dcm.metaAtrId = 3
	join cds_digContent_meta_valVoc dcmv on dcmv.metaValueId = dcm.metaValueId
	-- heigth
	join cds_digContent_meta dcm1 on dcm1.contentGuid = dc.contentGuid and dcm1.metaAtrId = 4
	join cds_digContent_meta_valVoc dcmv1 on dcmv1.metaValueId = dcm1.metaValueId
	-- image id
	join cds_digContent_meta dcm2 on dcm2.contentGuid = dc.contentGuid and dcm2.metaAtrId = 8
	join cds_digContent_meta_valVoc dcmv2 on dcmv2.metaValueId = dcm2.metaValueId
	where dl.prodid = 'S11328480' and dc.mediaTypeId = 15
	order by imageid, width) k


--how about a notebook

select * from cds_Prod where CatId = 'AB' limit 100;
'S10841413'
'S10858929'


select *
FROM   cds_digcontent dc
inner join cds_digcontent_links dl on dc.contentguid = dl.contentguid
where dl.prodid = 'S11328480' and dc.mediaTypeId = 15



select * from cds_prod where catid = 'AB' and mfid = 'Z11178'
select * from cds_Vocez where left(ID, 1) = 'Z' order by 2



pg_dump -U postgres -h localhost -t cds_digcontent_data wallmart | psql -d datasample_us -h localhost

--move table from wallmart to datasample_us
pg_dump -U postgres -W -h localhost -t cds_digcontent_data wallmart | psql -d datasample_us -h localhost -U postgres -W





select * from cds_Prod where Catid = 'AB'
select dsjson('S11328480');
select dsjson('S14495932');
select dsjson('S15028564');


--===============================================================================================================================


-- Function: bytea_import(text)

-- DROP FUNCTION bytea_import(text);

CREATE OR REPLACE FUNCTION bytea_import(IN p_path text, OUT p_result bytea)
  RETURNS bytea AS
$BODY$
declare
  l_oid oid;
  r record;
begin
  p_result := '';
  select lo_import(p_path) into l_oid;
  for r in ( select data 
             from pg_largeobject 
             where loid = l_oid 
             order by pageno ) loop
    p_result = p_result || r.data;
  end loop;
  perform lo_unlink(l_oid);
end;$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION bytea_import(text)
  OWNER TO postgres;

--===============================================================================================================================



-- Function: json_append(json, json)

-- DROP FUNCTION json_append(json, json);

CREATE OR REPLACE FUNCTION json_append(data json, insert_data json)
  RETURNS json AS
$BODY$
    SELECT ('{'||string_agg(to_json(key)||':'||value, ',')||'}')::json
    FROM (
        SELECT * FROM json_each(data)
        UNION ALL
        SELECT * FROM json_each(insert_data)
    ) t;
$BODY$
  LANGUAGE sql IMMUTABLE
  COST 100;
ALTER FUNCTION json_append(json, json)
  OWNER TO postgres;











