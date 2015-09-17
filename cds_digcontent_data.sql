-- Table: cds_digcontent_data

-- DROP TABLE cds_digcontent_data;

CREATE TABLE cds_digcontent_data
(
  contentguid character varying(36) NOT NULL,
  mediatypeid integer,
  content xml,
  CONSTRAINT pk_digcontent_data PRIMARY KEY (contentguid)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE cds_digcontent_data
  OWNER TO postgres;
