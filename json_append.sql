-- this is sourced from https://gist.github.com/matheusoliveira/9488951
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
