-- Quick Fix: Create APEX Workspace for Congressional Stock Tracker
-- Run this script in SQLcl or SQL Developer Web
-- 
-- Connect as: admin/<password>@CongressDB_high

SET SERVEROUTPUT ON

-- Step 1: Create dedicated schema for APEX workspace
PROMPT === Creating CONGRESS_SCHEMA ===
DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count
    FROM dba_users
    WHERE username = 'CONGRESS_SCHEMA';
    
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER CONGRESS_SCHEMA IDENTIFIED BY "ChangeMe123!"
            DEFAULT TABLESPACE DATA
            TEMPORARY TABLESPACE TEMP
            QUOTA UNLIMITED ON DATA';
        
        EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO CONGRESS_SCHEMA';
        EXECUTE IMMEDIATE 'GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, 
                          CREATE SEQUENCE, CREATE TRIGGER TO CONGRESS_SCHEMA';
        
        DBMS_OUTPUT.PUT_LINE('✓ Schema CONGRESS_SCHEMA created successfully.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✓ Schema CONGRESS_SCHEMA already exists.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error creating schema: ' || SQLERRM);
        RAISE;
END;
/

-- Step 2: Grant permissions on ADMIN objects to CONGRESS_SCHEMA
PROMPT === Granting permissions ===
BEGIN
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.CONGRESS_MEMBERS TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.STOCK_TRADES TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.STOCK_PRICES TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.INVESTMENT_OPPORTUNITIES TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.TRADE_ALERTS TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN.V_TOP_OPPORTUNITIES TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN.V_MEMBER_TRADING_ACTIVITY TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN.V_RECENT_TRADES TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT SELECT ON ADMIN.V_TICKER_ANALYSIS TO CONGRESS_SCHEMA';
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON ADMIN.CONGRESS_TRACKER_PKG TO CONGRESS_SCHEMA';
    
    DBMS_OUTPUT.PUT_LINE('✓ Permissions granted successfully.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error granting permissions: ' || SQLERRM);
END;
/

-- Step 3: Create synonyms in CONGRESS_SCHEMA
PROMPT === Creating synonyms ===
BEGIN
    FOR obj IN (SELECT 'CONGRESS_MEMBERS' as name FROM DUAL
                UNION ALL SELECT 'STOCK_TRADES' FROM DUAL
                UNION ALL SELECT 'STOCK_PRICES' FROM DUAL
                UNION ALL SELECT 'INVESTMENT_OPPORTUNITIES' FROM DUAL
                UNION ALL SELECT 'TRADE_ALERTS' FROM DUAL
                UNION ALL SELECT 'V_TOP_OPPORTUNITIES' FROM DUAL
                UNION ALL SELECT 'V_MEMBER_TRADING_ACTIVITY' FROM DUAL
                UNION ALL SELECT 'V_RECENT_TRADES' FROM DUAL
                UNION ALL SELECT 'V_TICKER_ANALYSIS' FROM DUAL
                UNION ALL SELECT 'CONGRESS_TRACKER_PKG' FROM DUAL) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'CREATE OR REPLACE SYNONYM CONGRESS_SCHEMA.' || obj.name || 
                            ' FOR ADMIN.' || obj.name;
            DBMS_OUTPUT.PUT_LINE('✓ Synonym created: ' || obj.name);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('  Note: ' || obj.name || ' - ' || SQLERRM);
        END;
    END LOOP;
END;
/

-- Step 4: Create APEX workspace
PROMPT === Creating APEX workspace ===
BEGIN
    APEX_INSTANCE_ADMIN.ADD_WORKSPACE(
        p_workspace_id   => NULL,
        p_workspace      => 'CONGRESS_TRACKER',
        p_primary_schema => 'CONGRESS_SCHEMA'
    );
    
    DBMS_OUTPUT.PUT_LINE('✓ Workspace CONGRESS_TRACKER created successfully.');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20001 AND SQLERRM LIKE '%already exists%' THEN
            DBMS_OUTPUT.PUT_LINE('✓ Workspace CONGRESS_TRACKER already exists.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('✗ Error creating workspace: ' || SQLERRM);
            RAISE;
        END IF;
END;
/

-- Step 5: Set security context and create admin user
PROMPT === Creating workspace admin user ===
DECLARE
    l_workspace_id NUMBER;
    l_user_exists NUMBER;
BEGIN
    -- Get workspace ID
    l_workspace_id := APEX_UTIL.FIND_SECURITY_GROUP_ID(p_workspace => 'CONGRESS_TRACKER');
    
    IF l_workspace_id IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('✗ ERROR: Could not find workspace CONGRESS_TRACKER');
        RETURN;
    END IF;
    
    -- Set security context
    APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => l_workspace_id);
    DBMS_OUTPUT.PUT_LINE('✓ Security context set for workspace.');
    
    -- Check if user exists
    SELECT COUNT(*) INTO l_user_exists
    FROM apex_workspace_apex_users
    WHERE user_name = 'CONGRESS_ADMIN'
    AND workspace_name = 'CONGRESS_TRACKER';
    
    IF l_user_exists > 0 THEN
        -- Update existing user
        APEX_UTIL.EDIT_USER(
            p_user_name                    => 'CONGRESS_ADMIN',
            p_email_address                => 'admin@congress-tracker.local',
            p_web_password                 => 'Welcome123!',
            p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
            p_change_password_on_first_use => 'N'
        );
        DBMS_OUTPUT.PUT_LINE('✓ User CONGRESS_ADMIN updated.');
    ELSE
        -- Create new user
        APEX_UTIL.CREATE_USER(
            p_user_name                    => 'CONGRESS_ADMIN',
            p_email_address                => 'admin@congress-tracker.local',
            p_web_password                 => 'Welcome123!',
            p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
            p_change_password_on_first_use => 'N'
        );
        DBMS_OUTPUT.PUT_LINE('✓ User CONGRESS_ADMIN created.');
    END IF;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('✓ All changes committed.');
END;
/

-- Step 6: Verification
PROMPT 
PROMPT ╔═══════════════════════════════════════════════════════════════════════╗
PROMPT ║                        VERIFICATION RESULTS                           ║
PROMPT ╚═══════════════════════════════════════════════════════════════════════╝
PROMPT 

PROMPT === Workspace Information ===
SELECT workspace_id, workspace, workspace_display_name
FROM apex_workspaces
WHERE workspace = 'CONGRESS_TRACKER';

PROMPT 
PROMPT === User Information ===
SELECT user_name, email, is_admin, developer_role, account_locked
FROM apex_workspace_apex_users
WHERE workspace_name = 'CONGRESS_TRACKER'
AND user_name = 'CONGRESS_ADMIN';

PROMPT 
PROMPT === Database Objects Access ===
SELECT 'Tables accessible: ' || COUNT(*) as info
FROM all_synonyms
WHERE owner = 'CONGRESS_SCHEMA'
AND table_owner = 'ADMIN';

PROMPT 
PROMPT ╔═══════════════════════════════════════════════════════════════════════╗
PROMPT ║                     SETUP COMPLETE!                                   ║
PROMPT ╚═══════════════════════════════════════════════════════════════════════╝
PROMPT 
PROMPT Login to APEX with:
PROMPT   Workspace: CONGRESS_TRACKER
PROMPT   Username:  CONGRESS_ADMIN
PROMPT   Password:  Welcome123!
PROMPT 
PROMPT IMPORTANT: Change the password after first login!
PROMPT 
PROMPT Next steps:
PROMPT   1. Access your APEX URL
PROMPT   2. Login with credentials above
PROMPT   3. Create your application in App Builder
PROMPT 

-- Done!
EXIT;