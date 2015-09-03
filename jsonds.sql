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

	v_mktd json;
	v_kspt json;
	v_witb json;
	v_pfts json;
	
	v_total json;
	v_start_time timestamp := now();
Begin
	raise notice 'starting process ... %', v_start_time;

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
