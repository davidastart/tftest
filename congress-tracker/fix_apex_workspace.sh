#!/bin/bash
################################################################################
# Fix APEX Workspace - Congressional Stock Tracker
# 
# This script fixes workspace visibility issues in APEX
#
# Run from OCI Cloud Shell after the initial deployment
################################################################################

set -e

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║           Fix APEX Workspace - Troubleshooting Script                ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# Gather Information
################################################################################

echo ""
print_info "Step 1: Gathering configuration information..."
echo ""

read -p "Enter your Autonomous Database OCID: " ADB_OCID
read -sp "Enter ADMIN password: " ADMIN_PASSWORD
echo ""
read -p "Enter database name (e.g., CongressDB): " DB_NAME

if [ -z "$DB_NAME" ]; then
    DB_NAME="CongressDB"
fi

WALLET_DIR="${HOME}/congress_tracker_wallet"

if [ ! -d "$WALLET_DIR" ]; then
    print_info "Wallet not found, downloading..."
    mkdir -p "$WALLET_DIR"
    oci db autonomous-database generate-wallet \
        --autonomous-database-id "$ADB_OCID" \
        --password "$ADMIN_PASSWORD" \
        --file "${WALLET_DIR}/wallet.zip"
    unzip -o "${WALLET_DIR}/wallet.zip" -d "$WALLET_DIR"
fi

DB_SERVICE="${DB_NAME}_high"
SQLCL="${HOME}/sqlcl/bin/sql"
export TNS_ADMIN="$WALLET_DIR"

################################################################################
# Check and Fix Workspace
################################################################################

echo ""
print_info "Step 2: Checking APEX configuration..."

cat > /tmp/check_workspace.sql << 'EOF'
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET PAGESIZE 0

-- Check APEX version
PROMPT === APEX Version ===
SELECT version_no FROM apex_release;

-- Check if workspace exists
PROMPT 
PROMPT === Checking Workspaces ===
SELECT workspace_id, workspace, workspace_display_name 
FROM apex_workspaces 
ORDER BY workspace_id;

-- Check if INTERNAL workspace is accessible
PROMPT 
PROMPT === INTERNAL Workspace Status ===
SELECT workspace_id, workspace 
FROM apex_workspaces 
WHERE workspace = 'INTERNAL';

EXIT;
EOF

print_info "Running diagnostics..."
$SQLCL -cloudconfig "$WALLET_DIR/wallet.zip" "admin/${ADMIN_PASSWORD}@${DB_SERVICE}" @/tmp/check_workspace.sql

################################################################################
# Create or Fix Workspace
################################################################################

echo ""
print_info "Step 3: Creating/Fixing APEX workspace..."

read -p "Enter workspace name to create (default: CONGRESS_TRACKER): " WORKSPACE_NAME
if [ -z "$WORKSPACE_NAME" ]; then
    WORKSPACE_NAME="CONGRESS_TRACKER"
fi

read -p "Enter workspace admin username (default: CONGRESS_ADMIN): " WORKSPACE_ADMIN
if [ -z "$WORKSPACE_ADMIN" ]; then
    WORKSPACE_ADMIN="CONGRESS_ADMIN"
fi

read -sp "Enter workspace admin password: " WORKSPACE_PASSWORD
echo ""

cat > /tmp/create_workspace.sql << EOF
SET SERVEROUTPUT ON

-- First, create a dedicated schema for the workspace (if it doesn't exist)
DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count
    FROM dba_users
    WHERE username = 'CONGRESS_SCHEMA';
    
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER CONGRESS_SCHEMA IDENTIFIED BY "${ADMIN_PASSWORD}"
            DEFAULT TABLESPACE DATA
            TEMPORARY TABLESPACE TEMP
            QUOTA UNLIMITED ON DATA';
        
        EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO CONGRESS_SCHEMA';
        EXECUTE IMMEDIATE 'GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, 
                          CREATE SEQUENCE, CREATE TRIGGER TO CONGRESS_SCHEMA';
        
        DBMS_OUTPUT.PUT_LINE('Schema CONGRESS_SCHEMA created successfully.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Schema CONGRESS_SCHEMA already exists.');
    END IF;
END;
/

-- Grant access to ADMIN schema objects
GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.CONGRESS_MEMBERS TO CONGRESS_SCHEMA;
GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.STOCK_TRADES TO CONGRESS_SCHEMA;
GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.STOCK_PRICES TO CONGRESS_SCHEMA;
GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.INVESTMENT_OPPORTUNITIES TO CONGRESS_SCHEMA;
GRANT SELECT, INSERT, UPDATE, DELETE ON ADMIN.TRADE_ALERTS TO CONGRESS_SCHEMA;
GRANT SELECT ON ADMIN.V_TOP_OPPORTUNITIES TO CONGRESS_SCHEMA;
GRANT SELECT ON ADMIN.V_MEMBER_TRADING_ACTIVITY TO CONGRESS_SCHEMA;
GRANT SELECT ON ADMIN.V_RECENT_TRADES TO CONGRESS_SCHEMA;
GRANT SELECT ON ADMIN.V_TICKER_ANALYSIS TO CONGRESS_SCHEMA;
GRANT EXECUTE ON ADMIN.CONGRESS_TRACKER_PKG TO CONGRESS_SCHEMA;

-- Create synonyms
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
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Synonym for ' || obj.name || ' already exists or error: ' || SQLERRM);
        END;
    END LOOP;
END;
/

-- Create the workspace
BEGIN
    BEGIN
        APEX_INSTANCE_ADMIN.ADD_WORKSPACE(
            p_workspace_id   => NULL,
            p_workspace      => '${WORKSPACE_NAME}',
            p_primary_schema => 'CONGRESS_SCHEMA'
        );
        DBMS_OUTPUT.PUT_LINE('Workspace ${WORKSPACE_NAME} created successfully.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN
                DBMS_OUTPUT.PUT_LINE('Workspace ${WORKSPACE_NAME} already exists.');
            ELSE
                DBMS_OUTPUT.PUT_LINE('Error creating workspace: ' || SQLERRM);
            END IF;
    END;
    
    COMMIT;
END;
/

-- Set the security group to the workspace
DECLARE
    l_workspace_id NUMBER;
BEGIN
    l_workspace_id := APEX_UTIL.FIND_SECURITY_GROUP_ID(p_workspace => '${WORKSPACE_NAME}');
    
    IF l_workspace_id IS NOT NULL THEN
        APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => l_workspace_id);
        DBMS_OUTPUT.PUT_LINE('Set security group ID to: ' || l_workspace_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('ERROR: Could not find workspace ${WORKSPACE_NAME}');
    END IF;
END;
/

-- Create or update the workspace admin user
DECLARE
    l_user_exists NUMBER;
BEGIN
    -- Check if user exists
    SELECT COUNT(*) INTO l_user_exists
    FROM apex_workspace_apex_users
    WHERE user_name = UPPER('${WORKSPACE_ADMIN}')
    AND workspace_name = '${WORKSPACE_NAME}';
    
    IF l_user_exists > 0 THEN
        -- Update existing user
        APEX_UTIL.EDIT_USER(
            p_user_name                    => '${WORKSPACE_ADMIN}',
            p_email_address                => 'admin@congress-tracker.local',
            p_web_password                 => '${WORKSPACE_PASSWORD}',
            p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
            p_change_password_on_first_use => 'N'
        );
        DBMS_OUTPUT.PUT_LINE('User ${WORKSPACE_ADMIN} updated successfully.');
    ELSE
        -- Create new user
        APEX_UTIL.CREATE_USER(
            p_user_name                    => '${WORKSPACE_ADMIN}',
            p_email_address                => 'admin@congress-tracker.local',
            p_web_password                 => '${WORKSPACE_PASSWORD}',
            p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
            p_change_password_on_first_use => 'N'
        );
        DBMS_OUTPUT.PUT_LINE('User ${WORKSPACE_ADMIN} created successfully.');
    END IF;
    
    COMMIT;
END;
/

-- Verify everything
PROMPT 
PROMPT === Verification ===
SELECT workspace, workspace_display_name, workspace_id
FROM apex_workspaces
WHERE workspace = '${WORKSPACE_NAME}';

SELECT user_name, email, is_admin, developer_role
FROM apex_workspace_apex_users
WHERE workspace_name = '${WORKSPACE_NAME}'
AND user_name = UPPER('${WORKSPACE_ADMIN}');

PROMPT 
PROMPT === All Workspaces ===
SELECT workspace_id, workspace, workspace_display_name
FROM apex_workspaces
ORDER BY workspace_id;

EXIT;
EOF

print_info "Creating/fixing workspace..."
$SQLCL -cloudconfig "$WALLET_DIR/wallet.zip" "admin/${ADMIN_PASSWORD}@${DB_SERVICE}" @/tmp/create_workspace.sql

################################################################################
# Get APEX URL
################################################################################

echo ""
print_info "Step 4: Getting APEX URL..."

ADB_INFO=$(oci db autonomous-database get --autonomous-database-id "$ADB_OCID" 2>/dev/null)

if [ $? -eq 0 ]; then
    APEX_URL=$(echo "$ADB_INFO" | grep -o '"apex-url":"[^"]*"' | grep -o 'https://[^"]*' | head -1)
    
    if [ -z "$APEX_URL" ]; then
        # Try alternative method
        CONNECTION_URLS=$(echo "$ADB_INFO" | grep -A 10 '"connection-urls"')
        APEX_URL=$(echo "$CONNECTION_URLS" | grep -o 'https://[^"]*apex[^"]*' | head -1)
    fi
    
    if [ -z "$APEX_URL" ]; then
        print_warning "Could not auto-detect APEX URL"
        APEX_URL="Check OCI Console -> Autonomous Database -> Tools -> Oracle APEX"
    fi
else
    APEX_URL="Check OCI Console -> Autonomous Database -> Tools -> Oracle APEX"
fi

################################################################################
# Summary
################################################################################

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                     Workspace Fix Complete!                          ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
print_success "Workspace configuration updated"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  APEX Login Information"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "  APEX URL:  $APEX_URL"
echo "  Workspace: $WORKSPACE_NAME"
echo "  Username:  $WORKSPACE_ADMIN"
echo "  Password:  <as configured>"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
print_info "How to login:"
echo "  1. Go to: $APEX_URL"
echo "  2. On the login page, you should see 'Workspace' field"
echo "  3. Enter:"
echo "     - Workspace: $WORKSPACE_NAME"
echo "     - Username: $WORKSPACE_ADMIN"
echo "     - Password: (your password)"
echo ""
print_warning "If you still don't see the workspace field:"
echo "  1. Try accessing the direct workspace URL:"
echo "     ${APEX_URL%/apex*}/ords/f?p=4550:1::::::"
echo "  2. Or append /apex to your database URL"
echo "  3. Clear browser cache and cookies"
echo "  4. Try a different browser or incognito mode"
echo ""
print_info "Alternative: Use INTERNAL workspace first"
echo "  1. Login with Workspace: INTERNAL"
echo "  2. Username: ADMIN"  
echo "  3. Password: Your database ADMIN password"
echo "  4. Then go to: Manage Workspaces > Existing Workspaces"
echo "  5. Find ${WORKSPACE_NAME} and verify it's there"
echo ""

cat > ~/apex_login_info.txt << EOF
APEX Login Information
=====================
Date: $(date)

APEX URL: $APEX_URL

Option 1: Direct Workspace Login
---------------------------------
Workspace: $WORKSPACE_NAME
Username: $WORKSPACE_ADMIN
Password: <your configured password>

Option 2: INTERNAL Workspace (Admin Access)
--------------------------------------------
Workspace: INTERNAL
Username: ADMIN
Password: <your database ADMIN password>

Then navigate to: Manage Workspaces > Existing Workspaces

Troubleshooting URLs:
---------------------
Direct workspace access: ${APEX_URL%/apex*}/ords/f?p=4550:1::::::
INTERNAL admin: ${APEX_URL}

Notes:
------
- If workspace field not visible, try the direct URL
- Clear browser cache if issues persist
- Use incognito/private mode to test
- Check that database is in AVAILABLE state
EOF

print_success "Login information saved to: ~/apex_login_info.txt"
echo ""

# Cleanup
rm -f /tmp/check_workspace.sql /tmp/create_workspace.sql

exit 0