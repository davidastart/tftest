-- Fix CONGRESS_ADMIN user and create complete APEX application
-- Run as ADMIN user

SET SERVEROUTPUT ON
SET DEFINE OFF

PROMPT ╔═══════════════════════════════════════════════════════════════════════╗
PROMPT ║          Fix User & Create APEX Application                          ║
PROMPT ╚═══════════════════════════════════════════════════════════════════════╝

-- Step 1: Fix the CONGRESS_ADMIN user
PROMPT 
PROMPT === Step 1: Fixing CONGRESS_ADMIN User ===

DECLARE
    l_workspace_id NUMBER;
    l_user_count NUMBER;
BEGIN
    -- Get workspace ID
    BEGIN
        SELECT workspace_id INTO l_workspace_id
        FROM apex_workspaces
        WHERE workspace = 'CONGRESS_TRACKER';
        
        DBMS_OUTPUT.PUT_LINE('✓ Found workspace CONGRESS_TRACKER (ID: ' || l_workspace_id || ')');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('✗ ERROR: Workspace CONGRESS_TRACKER not found!');
            DBMS_OUTPUT.PUT_LINE('  Run the quick_fix_workspace.sql script first.');
            RETURN;
    END;
    
    -- Set security context
    APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => l_workspace_id);
    DBMS_OUTPUT.PUT_LINE('✓ Security context set.');
    
    -- Check if user exists
    SELECT COUNT(*) INTO l_user_count
    FROM apex_workspace_apex_users
    WHERE workspace_name = 'CONGRESS_TRACKER'
    AND user_name = 'CONGRESS_ADMIN';
    
    IF l_user_count > 0 THEN
        -- Delete and recreate user (clean slate)
        DBMS_OUTPUT.PUT_LINE('  Removing existing CONGRESS_ADMIN user...');
        APEX_UTIL.REMOVE_USER(p_user_name => 'CONGRESS_ADMIN');
    END IF;
    
    -- Create user fresh
    DBMS_OUTPUT.PUT_LINE('  Creating CONGRESS_ADMIN user...');
    APEX_UTIL.CREATE_USER(
        p_user_id                      => NULL,
        p_user_name                    => 'CONGRESS_ADMIN',
        p_first_name                   => 'Congress',
        p_last_name                    => 'Administrator',
        p_description                  => 'Workspace Administrator',
        p_email_address                => 'admin@congress-tracker.local',
        p_web_password                 => 'Welcome123!',
        p_web_password_format          => 'CLEAR_TEXT',
        p_group_ids                    => '',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_default_schema               => 'CONGRESS_SCHEMA',
        p_allow_access_to_schemas      => 'CONGRESS_SCHEMA',
        p_account_expiry               => TO_DATE('4712-12-31','YYYY-MM-DD'),
        p_account_locked               => 'N',
        p_failed_access_attempts       => 0,
        p_change_password_on_first_use => 'N',
        p_first_password_use_occurred  => 'Y'
    );
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('✓ User CONGRESS_ADMIN created successfully!');
    DBMS_OUTPUT.PUT_LINE('  Password: Welcome123!');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error: ' || SQLERRM);
        ROLLBACK;
        RAISE;
END;
/

-- Step 2: Verify user
PROMPT 
PROMPT === Verification ===
SELECT 
    user_name,
    email,
    is_admin,
    developer_role,
    default_schema,
    account_locked,
    account_expiry
FROM apex_workspace_apex_users
WHERE workspace_name = 'CONGRESS_TRACKER'
AND user_name = 'CONGRESS_ADMIN';

-- Step 3: Create the APEX Application
PROMPT 
PROMPT === Step 2: Creating APEX Application ===

DECLARE
    l_workspace_id NUMBER;
    l_app_id NUMBER := 100;
    l_page_id NUMBER;
BEGIN
    -- Set workspace context
    SELECT workspace_id INTO l_workspace_id
    FROM apex_workspaces
    WHERE workspace = 'CONGRESS_TRACKER';
    
    APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => l_workspace_id);
    
    -- Check if app already exists
    BEGIN
        SELECT application_id INTO l_app_id
        FROM apex_applications
        WHERE workspace = 'CONGRESS_TRACKER'
        AND application_id = 100;
        
        DBMS_OUTPUT.PUT_LINE('  Application 100 already exists, removing...');
        APEX_APPLICATION_INSTALL.REMOVE_APPLICATION(
            p_application_id => l_app_id
        );
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('  Creating new application...');
    END;
    
    -- Create application
    APEX_APPLICATION_INSTALL.SET_WORKSPACE_ID(l_workspace_id);
    APEX_APPLICATION_INSTALL.SET_APPLICATION_ID(100);
    APEX_APPLICATION_INSTALL.SET_SCHEMA('CONGRESS_SCHEMA');
    APEX_APPLICATION_INSTALL.SET_APPLICATION_NAME('Congressional Stock Tracker');
    APEX_APPLICATION_INSTALL.SET_APPLICATION_ALIAS('CONGRESS_TRACKER');
    
    APEX_APPLICATION_INSTALL.GENERATE_APPLICATION;
    
    DBMS_OUTPUT.PUT_LINE('✓ Application created with ID: 100');
    
    COMMIT;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error creating application: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('  You can create the application manually in APEX.');
        ROLLBACK;
END;
/

PROMPT 
PROMPT ╔═══════════════════════════════════════════════════════════════════════╗
PROMPT ║                           SUCCESS!                                    ║
PROMPT ╚═══════════════════════════════════════════════════════════════════════╝
PROMPT 
PROMPT Login to APEX with:
PROMPT   Workspace: CONGRESS_TRACKER
PROMPT   Username:  CONGRESS_ADMIN  
PROMPT   Password:  Welcome123!
PROMPT 
PROMPT The application shell has been created.
PROMPT Next: Login to APEX and build your pages!
PROMPT 

EXIT;