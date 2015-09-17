# jsonds

Introduction:
Just a stored proc to generate DataSource API in JSON format.

Requirements:
PostGreSql ver 9.4+

Instructions:
Steps to enable DataSource API in PostGreSQL

1) Create digital content (xml) content table - cds_digcontent_data.sql (schema folder)

2) Create functions (functions folder)
	a) json_append.sql (append json)
	b) bytea_import.sql (needed to read XML from filesystem into DB)
	c) dsjson.sql (main stored procedure for generating JSON fr DataSource)

3) Run the ContentConnector with option to download digital content 
	Specifically these options must be set to true
	<MediaType ID="4" Directory="MARKETING_TEXT" Description="Localized marketing text"/>
	<MediaType ID="5" Directory="KEY_SELLING_POINTS" Description="Key selling points"/>
	<MediaType ID="10" Directory="WHATS_IN_THE_BOX" Description="What's in the Box"/>
	<MediaType ID="11" Directory="PRODUCT_DATA_SHEET" Description="Product data sheet"/>
	<MediaType ID="12" Directory="USER_MANUAL" Description="User manual"/>
	<MediaType ID="13" Directory="QUICK_START_GUID" Description="Quick start guide"/>
	<MediaType ID="14" Directory="PRODUCT_FEATURES" Description="Product features"/>	

4) After the ContentConnector had finished downloading the required (XML) digital content above, these need to be imported into the "cds_digcontent_data" table. 
	a) Log into postgres  		  # psql -U postgres_user -W -d databasename
	b) Set output to file 		  # \o dc_import.sql
	c) Remove header / footer 	# \pset tuples_only
	d) Generate SQL into file for loading all required XML into the "cds_digcontent_data" table. Run the below SQL. It will generate SQL insert statements inserting the XML into the "cds_digcontent_data" table.

	with dc_import as (
		select distinct contentguid as contentguid, mediatypeid, 
		('/path/to/connector/data/digitalcontent/folder' ||
			case mediatypeid
				when 4 then '/MARKETING_TEXT/'
				when 5 then '/KEY_SELLING_POINTS/'
				when 10 then '/WHATS_IN_THE_BOX/'
				when 14 then '/PRODUCT_FEATURES/'
			end || contentguid || '.xml') as xmlcontent
		from cds_digcontent 
		where mediatypeid in (4,5,10,14)
		)
	Select 'insert into cds_digcontent_data (contentguid, mediatypeid, content) values  (''' || contentguid || ''',' || mediatypeid
	|| ',convert_from(bytea_import(''' || xmlcontent || '''), ''utf8'')::xml);'
	from dc_import;	

	e) Inspect the file 	# head dc_import.sql
	Should look something like the below:-

insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('F07F1FDD-A7E5-48AA-8C08-480A606C19CD',4,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/MARKETING_TEXT/F07F1FDD-A7E5-48AA-8C08-480A606C19CD.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('960C7D26-02E7-49D0-B598-98038960F646',14,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/PRODUCT_FEATURES/960C7D26-02E7-49D0-B598-98038960F646.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('1119DDF4-B045-49D0-BCA1-25795B1BAD59',10,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/WHATS_IN_THE_BOX/1119DDF4-B045-49D0-BCA1-25795B1BAD59.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('7D69A559-0644-44A0-BF5C-487A1935F0DA',4,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/MARKETING_TEXT/7D69A559-0644-44A0-BF5C-487A1935F0DA.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('6A0AA3E4-A899-43EC-AB02-9AB7BC971682',4,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/MARKETING_TEXT/6A0AA3E4-A899-43EC-AB02-9AB7BC971682.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('77B34CBD-3C3A-49BB-8C89-AFD545CFD7FA',4,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/MARKETING_TEXT/77B34CBD-3C3A-49BB-8C89-AFD545CFD7FA.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('F2176A6E-F18B-4426-894C-6B0F9E8F14AB',14,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/PRODUCT_FEATURES/F2176A6E-F18B-4426-894C-6B0F9E8F14AB.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('2CB22927-2CF7-4415-B6FC-356E40E56339',4,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/MARKETING_TEXT/2CB22927-2CF7-4415-B6FC-356E40E56339.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('9B9D8674-5941-4E19-A996-3173A259526C',10,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/WHATS_IN_THE_BOX/9B9D8674-5941-4E19-A996-3173A259526C.xml'), 'utf8')::xml);
insert into cds_digcontent_data (contentguid, mediatypeid, content) values  ('FBC290D6-7C7B-4D0D-B1E6-D61495DB9CC8',4,convert_from(bytea_import('/path/to/connector/data/digitalcontent/folder/MARKETING_TEXT/FBC290D6-7C7B-4D0D-B1E6-D61495DB9CC8.xml'), 'utf8')::xml);

	Try & run a couple of statements, make sure they run OK. Then remember to truncate the test data.

	f) Import the digital content into the database # psql -U postgres_user -W -d databasename < dc_import.sql

5) Run the "dsjson" function with a single parameter (product_id)
	select dsjson('S11328480');

An example of the output can be found in the /sample folder. This json had been pretty printed, but does not look that way right out of psql.
