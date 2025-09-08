CREATE USER "TESTUSER" IDENTIFIED BY Thisisapassword3#;

GRANT CREATE SESSION TO "TESTUSER";

ALTER USER "TESTUSER" ACCOUNT UNLOCK;

GRANT CONNECT, RESOURCE, DWROLE TO  "TESTUSER";

GRANT UNLIMITED TABLESPACE TO "TESTUSER";

BEGIN
    ORDS.ENABLE_SCHEMA(p_enabled => TRUE,
                       p_schema => 'TESTUSER',
                       p_url_mapping_type => 'BASE_PATH',
                       p_url_mapping_pattern => 'TESTUSER',
                       p_auto_rest_auth => FALSE);
    commit;
END;
/