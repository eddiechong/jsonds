
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

	v_tmp json;
	
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
		select 
			json_build_object('lines', json_agg(dat)) into v_mktd
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
		select json_build_object('ccs-in-the-box', 
			json_build_object('lines', json_agg(dat))) into v_witb
		from
			(SELECT cast(unnest(xpath('/body/ul/li/text()', content)) as text) as dat
			FROM   cds_digcontent_data c
			inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
			where prodid= pid  and mediatypeid = 10) k;
	End;
		
	Begin
	
		--building product features
		select json_build_object('items', json_agg(ft)) into v_pfts
		from
			(select json_build_object('name', nm, 'lines', ln) as ft
			from
				(SELECT unnest(xpath('/body/ul/li/strong/text()', content)) as nm, 
					unnest(xpath('/body/ul/li/text()', content)) as ln
				FROM   cds_digcontent_data c
				inner join cds_digcontent_links l on c.contentguid = lower(l.contentguid)
				where l.prodid= 'S11328480' and mediatypeid = 14) x) y;
			
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
	select json_append(v_total, json_build_object('ccs-standard-image', x)) from v_stdimg x into v_total;

	--adding ccs-mkt-desc
	select json_append(v_total, json_build_object('ccs-mkt-desc', v_mktd)) into v_total;

	--ccs-in-the-box:	
	select json_append(v_total, v_witb) into v_total;

	--ccs-features
	select json_append(v_total, json_build_object('ccs-features', v_pfts)) into v_total;

	--ccs-ksp-features
	select json_append(v_total, json_build_object('ccs-ksp-features', 
					json_build_object('features',
						json_append(json_build_object('head', 'Product Features'), v_pfts)))) into v_total;


	select json_append(v_tmp, json_build_object('mktDesc', json_append(json_build_object('name', 'Marketing Description'), v_mktd))) into v_tmp;

	select json_append(v_tmp, json_build_object('features', json_append(json_build_object('head', 'Product Features'), v_pfts))) into v_tmp;

	--ccs-mkt-ksp-features
	select json_append(v_total, json_build_object('ccs-mkt-ksp-features', v_tmp)) into v_total;

	select json_append(v_total, v_std) into v_total;
	
	select json_append(v_total, v_main) into v_total;
	select json_append(v_total, v_extd) into v_total;
	
	return v_total;
End;
$$ LANGUAGE plpgsql;


--select dsjson('S11328480');



