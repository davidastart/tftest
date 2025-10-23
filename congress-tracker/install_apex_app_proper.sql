-- Install Congressional Stock Tracker APEX Application
-- Run this as: sql -cloudconfig wallet.zip admin/password@service @install_apex_app.sql

SET SERVEROUTPUT ON
SET DEFINE OFF

PROMPT ╔═══════════════════════════════════════════════════════════════════════╗
PROMPT ║     Install Congressional Stock Tracker APEX Application            ║
PROMPT ╚═══════════════════════════════════════════════════════════════════════╝

-- Step 1: Set workspace context
DECLARE
    l_workspace_id NUMBER;
    l_app_id NUMBER := 100;
BEGIN
    -- Get workspace ID
    SELECT workspace_id INTO l_workspace_id
    FROM apex_workspaces
    WHERE workspace = 'CONGRESS_TRACKER';
    
    DBMS_OUTPUT.PUT_LINE('✓ Found workspace CONGRESS_TRACKER (ID: ' || l_workspace_id || ')');
    
    -- Set security context
    APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => l_workspace_id);
    APEX_UTIL.SET_WORKSPACE('CONGRESS_TRACKER');
    
    DBMS_OUTPUT.PUT_LINE('✓ Security context set');
    
    -- Check if app already exists and delete it
    BEGIN
        SELECT application_id INTO l_app_id
        FROM apex_applications
        WHERE workspace = 'CONGRESS_TRACKER'
        AND application_id = 100;
        
        DBMS_OUTPUT.PUT_LINE('  Removing existing application...');
        
        -- Delete the application
        APEX_APPLICATION_ADMIN.REMOVE_APPLICATION(
            p_application_id => l_app_id,
            p_remove_subscriptions => TRUE
        );
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('✓ Existing application removed');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('  No existing application to remove');
    END;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error: ' || SQLERRM);
        RAISE;
END;
/

-- Step 2: Create the application
DECLARE
    l_workspace_id NUMBER;
    l_app_id NUMBER := 100;
BEGIN
    -- Get workspace context
    SELECT workspace_id INTO l_workspace_id
    FROM apex_workspaces
    WHERE workspace = 'CONGRESS_TRACKER';
    
    APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => l_workspace_id);
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Creating application...');
    
    -- Create application using simplified API
    l_app_id := APEX_APPLICATION_ADMIN.CREATE_APPLICATION(
        p_application_name => 'Congressional Stock Tracker',
        p_application_alias => 'CONGRESS_TRACKER',
        p_application_group => NULL,
        p_schema => 'CONGRESS_SCHEMA'
    );
    
    DBMS_OUTPUT.PUT_LINE('✓ Application created with ID: ' || l_app_id);
    
    COMMIT;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error creating application: ' || SQLERRM);
        ROLLBACK;
        RAISE;
END;
/

-- Step 3: Create pages using APEX APIs
DECLARE
    l_workspace_id NUMBER;
    l_app_id NUMBER := 100;
    l_page_id NUMBER;
    l_region_id NUMBER;
BEGIN
    SELECT workspace_id INTO l_workspace_id
    FROM apex_workspaces
    WHERE workspace = 'CONGRESS_TRACKER';
    
    APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => l_workspace_id);
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Creating pages...');
    
    -- Page 1: Dashboard
    l_page_id := APEX_APPLICATION_ADMIN.CREATE_PAGE(
        p_application_id => l_app_id,
        p_page_id => 1,
        p_page_name => 'Dashboard',
        p_page_alias => 'HOME'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Created Page 1: Dashboard');
    
    -- Page 2: Opportunities
    l_page_id := APEX_APPLICATION_ADMIN.CREATE_PAGE(
        p_application_id => l_app_id,
        p_page_id => 2,
        p_page_name => 'Investment Opportunities',
        p_page_alias => 'OPPORTUNITIES',
        p_page_mode => 'REPORT',
        p_report_implementation => 'INTERACTIVE_REPORT',
        p_table_name => 'V_TOP_OPPORTUNITIES'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Created Page 2: Investment Opportunities');
    
    -- Page 3: Recent Trades
    l_page_id := APEX_APPLICATION_ADMIN.CREATE_PAGE(
        p_application_id => l_app_id,
        p_page_id => 3,
        p_page_name => 'Recent Trades',
        p_page_alias => 'TRADES',
        p_page_mode => 'REPORT',
        p_report_implementation => 'INTERACTIVE_REPORT',
        p_table_name => 'V_RECENT_TRADES'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Created Page 3: Recent Trades');
    
    -- Page 4: Member Analysis
    l_page_id := APEX_APPLICATION_ADMIN.CREATE_PAGE(
        p_application_id => l_app_id,
        p_page_id => 4,
        p_page_name => 'Member Analysis',
        p_page_alias => 'MEMBERS',
        p_page_mode => 'REPORT',
        p_report_implementation => 'INTERACTIVE_REPORT',
        p_table_name => 'V_MEMBER_TRADING_ACTIVITY'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Created Page 4: Member Analysis');
    
    -- Page 6: Alerts
    l_page_id := APEX_APPLICATION_ADMIN.CREATE_PAGE(
        p_application_id => l_app_id,
        p_page_id => 6,
        p_page_name => 'Alerts',
        p_page_alias => 'ALERTS',
        p_page_mode => 'REPORT',
        p_report_implementation => 'INTERACTIVE_REPORT',
        p_table_name => 'TRADE_ALERTS'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Created Page 6: Alerts');
    
    -- Page 7: Admin
    l_page_id := APEX_APPLICATION_ADMIN.CREATE_PAGE(
        p_application_id => l_app_id,
        p_page_id => 7,
        p_page_name => 'Admin Panel',
        p_page_alias => 'ADMIN'
    );
    DBMS_OUTPUT.PUT_LINE('✓ Created Page 7: Admin Panel');
    
    COMMIT;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('✗ Error creating pages: ' || SQLERRM);
        ROLLBACK;
        RAISE;
END;
/

-- Step 4: Verify installation
PROMPT 
PROMPT ═══════════════════════════════════════════════════════════════════════
PROMPT   Verification
PROMPT ═══════════════════════════════════════════════════════════════════════

SELECT 
    application_id,
    application_name,
    owner,
    version
FROM apex_applications
WHERE workspace = 'CONGRESS_TRACKER'
ORDER BY application_id;

PROMPT 
PROMPT === Application Pages ===
SELECT 
    page_id,
    page_name,
    page_alias
FROM apex_application_pages
WHERE application_id = 100
ORDER BY page_id;

PROMPT 
PROMPT ╔═══════════════════════════════════════════════════════════════════════╗
PROMPT ║                    Installation Complete!                             ║
PROMPT ╚═══════════════════════════════════════════════════════════════════════╝
PROMPT 
PROMPT Access your application:
PROMPT   1. Login to APEX workspace CONGRESS_TRACKER
PROMPT   2. Go to App Builder
PROMPT   3. Click on "Congressional Stock Tracker"
PROMPT   4. Click "Run Application"
PROMPT 
PROMPT You can now customize pages in App Builder!
PROMPT 

EXIT;