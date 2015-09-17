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
