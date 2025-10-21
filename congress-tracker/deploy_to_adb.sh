#!/bin/bash
################################################################################
# Congressional Stock Tracker - Oracle Autonomous Database Deployment Script
# 
# This script deploys the entire application to Oracle Autonomous Database
# Run from OCI Cloud Shell
#
# Prerequisites:
# 1. Oracle Autonomous Database (ATP or ADW) already created in OCI
# 2. ADMIN password for the database
# 3. OCI CLI configured (automatically available in Cloud Shell)
#
# Usage:
#   chmod +x deploy_to_adb.sh
#   ./deploy_to_adb.sh
################################################################################

set -e  # Exit on error

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║  Congressional Stock Tracker - Autonomous Database Deployment        ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
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
# Step 1: Gather Required Information
################################################################################

echo ""
print_info "Step 1: Gathering configuration information..."
echo ""

# Get Autonomous Database OCID
read -p "Enter your Autonomous Database OCID: " ADB_OCID

if [ -z "$ADB_OCID" ]; then
    print_error "Database OCID is required!"
    exit 1
fi

# Get ADMIN password
read -sp "Enter ADMIN password for the database: " ADMIN_PASSWORD
echo ""

if [ -z "$ADMIN_PASSWORD" ]; then
    print_error "ADMIN password is required!"
    exit 1
fi

# Get database name
read -p "Enter the database name (e.g., CongressDB): " DB_NAME

if [ -z "$DB_NAME" ]; then
    DB_NAME="CongressDB"
fi

# Get workspace name
read -p "Enter APEX workspace name (default: CONGRESS_TRACKER): " WORKSPACE_NAME

if [ -z "$WORKSPACE_NAME" ]; then
    WORKSPACE_NAME="CONGRESS_TRACKER"
fi

# Get workspace admin username
read -p "Enter APEX workspace admin username (default: CONGRESS_ADMIN): " WORKSPACE_ADMIN

if [ -z "$WORKSPACE_ADMIN" ]; then
    WORKSPACE_ADMIN="CONGRESS_ADMIN"
fi

# Get workspace admin password
read -sp "Enter APEX workspace admin password: " WORKSPACE_PASSWORD
echo ""

if [ -z "$WORKSPACE_PASSWORD" ]; then
    print_error "Workspace admin password is required!"
    exit 1
fi

################################################################################
# Step 2: Download Wallet for Database Connection
################################################################################

echo ""
print_info "Step 2: Downloading database wallet..."

WALLET_DIR="${HOME}/congress_tracker_wallet"
mkdir -p "$WALLET_DIR"

# Download wallet using OCI CLI
oci db autonomous-database generate-wallet \
    --autonomous-database-id "$ADB_OCID" \
    --password "$ADMIN_PASSWORD" \
    --file "${WALLET_DIR}/wallet.zip"

if [ $? -ne 0 ]; then
    print_error "Failed to download wallet!"
    exit 1
fi

# Extract wallet
unzip -o "${WALLET_DIR}/wallet.zip" -d "$WALLET_DIR"
print_success "Wallet downloaded and extracted to $WALLET_DIR"

# Get connection string from tnsnames.ora
DB_SERVICE=$(grep -m 1 "${DB_NAME}_high" "${WALLET_DIR}/tnsnames.ora" | cut -d'=' -f1 | tr -d ' ')

if [ -z "$DB_SERVICE" ]; then
    DB_SERVICE="${DB_NAME}_high"
fi

print_info "Using database service: $DB_SERVICE"

################################################################################
# Step 3: Install SQLcl if not available
################################################################################

echo ""
print_info "Step 3: Setting up SQLcl..."

SQLCL_DIR="${HOME}/sqlcl"

if [ ! -d "$SQLCL_DIR" ]; then
    print_info "Downloading SQLcl..."
    cd ~
    wget -q https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip
    unzip -q sqlcl-latest.zip
    rm sqlcl-latest.zip
    print_success "SQLcl installed"
else
    print_info "SQLcl already installed"
fi

SQLCL="${SQLCL_DIR}/bin/sql"
export TNS_ADMIN="$WALLET_DIR"

################################################################################
# Step 4: Create Database Schema
################################################################################

echo ""
print_info "Step 4: Creating database schema..."

# Create SQL script
cat > /tmp/init_schema.sql << 'EOF'
-- Congressional Stock Tracker Schema

-- Create tables
CREATE TABLE congress_members (
    member_id VARCHAR2(50) PRIMARY KEY,
    first_name VARCHAR2(100),
    last_name VARCHAR2(100),
    party VARCHAR2(20),
    state VARCHAR2(2),
    chamber VARCHAR2(20),
    photo_url VARCHAR2(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE stock_trades (
    trade_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    member_id VARCHAR2(50),
    ticker VARCHAR2(10),
    transaction_date DATE,
    disclosure_date DATE,
    transaction_type VARCHAR2(20),
    amount_range VARCHAR2(50),
    amount_min NUMBER(12,2),
    amount_max NUMBER(12,2),
    asset_description VARCHAR2(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_member FOREIGN KEY (member_id) 
        REFERENCES congress_members(member_id)
);

CREATE TABLE stock_prices (
    price_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticker VARCHAR2(10),
    price_date DATE,
    open_price NUMBER(10,2),
    high_price NUMBER(10,2),
    low_price NUMBER(10,2),
    close_price NUMBER(10,2),
    volume NUMBER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_ticker_date UNIQUE (ticker, price_date)
);

CREATE TABLE investment_opportunities (
    opportunity_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticker VARCHAR2(10),
    company_name VARCHAR2(200),
    trade_date DATE,
    current_price NUMBER(10,2),
    trade_disclosure_price NUMBER(10,2),
    price_change_pct NUMBER(5,2),
    num_purchases NUMBER,
    num_members NUMBER,
    total_volume NUMBER,
    opportunity_score NUMBER(5,2),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE trade_alerts (
    alert_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticker VARCHAR2(10),
    alert_type VARCHAR2(50),
    alert_message VARCHAR2(4000),
    is_read VARCHAR2(1) DEFAULT 'N',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_trades_ticker ON stock_trades(ticker);
CREATE INDEX idx_trades_date ON stock_trades(transaction_date);
CREATE INDEX idx_trades_member ON stock_trades(member_id);
CREATE INDEX idx_prices_ticker ON stock_prices(ticker);
CREATE INDEX idx_prices_date ON stock_prices(price_date);
CREATE INDEX idx_opps_score ON investment_opportunities(opportunity_score DESC);
CREATE INDEX idx_alerts_created ON trade_alerts(created_at DESC);

-- Create views
CREATE OR REPLACE VIEW v_top_opportunities AS
SELECT 
    o.opportunity_id,
    o.ticker,
    o.company_name,
    o.current_price,
    o.trade_disclosure_price,
    o.price_change_pct,
    o.num_purchases,
    o.num_members,
    o.opportunity_score,
    o.trade_date,
    o.last_updated,
    CASE 
        WHEN o.opportunity_score >= 80 THEN 'High'
        WHEN o.opportunity_score >= 60 THEN 'Medium'
        ELSE 'Low'
    END as priority_level
FROM investment_opportunities o
ORDER BY o.opportunity_score DESC;

CREATE OR REPLACE VIEW v_member_trading_activity AS
SELECT 
    m.member_id,
    m.first_name || ' ' || m.last_name as member_name,
    m.party,
    m.state,
    m.chamber,
    COUNT(DISTINCT t.ticker) as unique_tickers_traded,
    COUNT(*) as total_trades,
    SUM(CASE WHEN t.transaction_type = 'Purchase' THEN 1 ELSE 0 END) as purchases,
    SUM(CASE WHEN t.transaction_type = 'Sale' THEN 1 ELSE 0 END) as sales,
    MAX(t.transaction_date) as last_trade_date
FROM congress_members m
LEFT JOIN stock_trades t ON m.member_id = t.member_id
GROUP BY m.member_id, m.first_name, m.last_name, m.party, m.state, m.chamber;

CREATE OR REPLACE VIEW v_recent_trades AS
SELECT 
    t.trade_id,
    t.ticker,
    t.transaction_date,
    t.disclosure_date,
    t.transaction_type,
    t.amount_range,
    t.asset_description,
    m.first_name || ' ' || m.last_name as member_name,
    m.party,
    m.state,
    m.chamber,
    p.close_price as price_at_trade,
    p_current.close_price as current_price,
    ROUND(((p_current.close_price - p.close_price) / p.close_price * 100), 2) as price_change_pct
FROM stock_trades t
JOIN congress_members m ON t.member_id = m.member_id
LEFT JOIN stock_prices p ON t.ticker = p.ticker AND p.price_date = t.transaction_date
LEFT JOIN stock_prices p_current ON t.ticker = p_current.ticker 
    AND p_current.price_date = (SELECT MAX(price_date) FROM stock_prices WHERE ticker = t.ticker)
ORDER BY t.transaction_date DESC;

CREATE OR REPLACE VIEW v_ticker_analysis AS
SELECT 
    t.ticker,
    COUNT(DISTINCT t.member_id) as num_members_trading,
    COUNT(*) as total_trades,
    SUM(CASE WHEN t.transaction_type = 'Purchase' THEN 1 ELSE 0 END) as total_purchases,
    SUM(CASE WHEN t.transaction_type = 'Sale' THEN 1 ELSE 0 END) as total_sales,
    MIN(t.transaction_date) as first_trade_date,
    MAX(t.transaction_date) as last_trade_date,
    AVG(p.close_price) as avg_price,
    MIN(p.close_price) as min_price,
    MAX(p.close_price) as max_price
FROM stock_trades t
LEFT JOIN stock_prices p ON t.ticker = p.ticker
WHERE t.transaction_date >= ADD_MONTHS(SYSDATE, -6)
GROUP BY t.ticker;

-- Create PL/SQL package
CREATE OR REPLACE PACKAGE congress_tracker_pkg AS
    PROCEDURE refresh_opportunities;
    PROCEDURE cleanup_old_data(p_days_to_keep NUMBER DEFAULT 365);
    FUNCTION get_opportunity_trend(p_ticker VARCHAR2) RETURN VARCHAR2;
    PROCEDURE create_alert(p_ticker VARCHAR2, p_alert_type VARCHAR2, p_message VARCHAR2);
    PROCEDURE fetch_stock_prices(p_ticker VARCHAR2);
END congress_tracker_pkg;
/

CREATE OR REPLACE PACKAGE BODY congress_tracker_pkg AS

    PROCEDURE refresh_opportunities IS
    BEGIN
        DELETE FROM investment_opportunities;
        
        INSERT INTO investment_opportunities 
        (ticker, company_name, trade_date, current_price, trade_disclosure_price, 
         price_change_pct, num_purchases, num_members, opportunity_score)
        SELECT 
            t.ticker,
            MAX(t.asset_description) as company_name,
            MAX(t.transaction_date) as trade_date,
            p_current.close_price as current_price,
            AVG(p_trade.close_price) as trade_disclosure_price,
            ROUND(((p_current.close_price - AVG(p_trade.close_price)) / 
                   AVG(p_trade.close_price) * 100), 2) as price_change_pct,
            COUNT(*) as num_purchases,
            COUNT(DISTINCT t.member_id) as num_members,
            (COUNT(DISTINCT t.member_id) * 10 - 
             ABS((p_current.close_price - AVG(p_trade.close_price)) / 
                 AVG(p_trade.close_price) * 100)) as opportunity_score
        FROM stock_trades t
        JOIN stock_prices p_trade 
            ON t.ticker = p_trade.ticker 
            AND p_trade.price_date = t.transaction_date
        JOIN stock_prices p_current 
            ON t.ticker = p_current.ticker 
            AND p_current.price_date = (SELECT MAX(price_date) 
                                        FROM stock_prices 
                                        WHERE ticker = t.ticker)
        WHERE t.transaction_type = 'Purchase'
            AND t.transaction_date >= SYSDATE - 30
            AND ((p_current.close_price - p_trade.close_price) / 
                 p_trade.close_price * 100) < 5
        GROUP BY t.ticker, p_current.close_price
        HAVING COUNT(*) >= 2;
        
        COMMIT;
    END refresh_opportunities;
    
    PROCEDURE cleanup_old_data(p_days_to_keep NUMBER DEFAULT 365) IS
    BEGIN
        DELETE FROM stock_prices 
        WHERE price_date < SYSDATE - p_days_to_keep;
        
        DELETE FROM trade_alerts 
        WHERE created_at < SYSDATE - 30;
        
        COMMIT;
    END cleanup_old_data;
    
    FUNCTION get_opportunity_trend(p_ticker VARCHAR2) RETURN VARCHAR2 IS
        v_recent_score NUMBER;
    BEGIN
        SELECT opportunity_score INTO v_recent_score
        FROM investment_opportunities
        WHERE ticker = p_ticker;
        
        RETURN CASE 
            WHEN v_recent_score > 70 THEN 'Rising'
            WHEN v_recent_score < 40 THEN 'Falling'
            ELSE 'Stable'
        END;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'Unknown';
    END get_opportunity_trend;
    
    PROCEDURE create_alert(p_ticker VARCHAR2, p_alert_type VARCHAR2, p_message VARCHAR2) IS
    BEGIN
        INSERT INTO trade_alerts (ticker, alert_type, alert_message)
        VALUES (p_ticker, p_alert_type, p_message);
        COMMIT;
    END create_alert;
    
    PROCEDURE fetch_stock_prices(p_ticker VARCHAR2) IS
        l_url VARCHAR2(4000);
        l_response CLOB;
    BEGIN
        -- This would call external API using APEX_WEB_SERVICE
        -- Simplified version - you'll integrate with actual stock API
        l_url := 'https://query1.finance.yahoo.com/v8/finance/chart/' || p_ticker;
        
        -- Use APEX_WEB_SERVICE.MAKE_REST_REQUEST in production
        NULL;
    END fetch_stock_prices;

END congress_tracker_pkg;
/

-- Create scheduler job
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'REFRESH_OPPORTUNITIES_JOB',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN congress_tracker_pkg.refresh_opportunities; END;',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=HOURLY; INTERVAL=1',
        enabled         => TRUE,
        comments        => 'Refresh investment opportunities every hour'
    );
END;
/

COMMIT;
EOF

# Execute SQL script
print_info "Executing schema creation script..."
$SQLCL -cloudconfig "$WALLET_DIR/wallet.zip" "admin/${ADMIN_PASSWORD}@${DB_SERVICE}" @/tmp/init_schema.sql

if [ $? -eq 0 ]; then
    print_success "Database schema created successfully"
else
    print_error "Failed to create database schema"
    exit 1
fi

################################################################################
# Step 5: Create APEX Workspace
################################################################################

echo ""
print_info "Step 5: Creating APEX workspace..."

cat > /tmp/create_workspace.sql << EOF
BEGIN
    APEX_INSTANCE_ADMIN.ADD_WORKSPACE(
        p_workspace_id   => NULL,
        p_workspace      => '${WORKSPACE_NAME}',
        p_primary_schema => 'ADMIN'
    );
    
    APEX_UTIL.SET_SECURITY_GROUP_ID(
        p_security_group_id => APEX_UTIL.FIND_SECURITY_GROUP_ID(
            p_workspace => '${WORKSPACE_NAME}'
        )
    );
    
    APEX_UTIL.CREATE_USER(
        p_user_name                    => '${WORKSPACE_ADMIN}',
        p_email_address                => 'admin@congress-tracker.local',
        p_web_password                 => '${WORKSPACE_PASSWORD}',
        p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_change_password_on_first_use => 'N'
    );
    
    COMMIT;
END;
/
EOF

$SQLCL -cloudconfig "$WALLET_DIR/wallet.zip" "admin/${ADMIN_PASSWORD}@${DB_SERVICE}" @/tmp/create_workspace.sql

if [ $? -eq 0 ]; then
    print_success "APEX workspace created successfully"
else
    print_warning "Workspace may already exist or failed to create"
fi

################################################################################
# Step 6: Get APEX URL
################################################################################

echo ""
print_info "Step 6: Getting APEX URL..."

# Get the ADB details
ADB_INFO=$(oci db autonomous-database get --autonomous-database-id "$ADB_OCID" 2>/dev/null)

if [ $? -eq 0 ]; then
    APEX_URL=$(echo "$ADB_INFO" | grep -o '"connection-urls":.*"apex-url":"[^"]*"' | grep -o 'https://[^"]*' | head -1)
    
    if [ ! -z "$APEX_URL" ]; then
        print_success "APEX URL retrieved successfully"
    else
        print_warning "Could not retrieve APEX URL automatically"
        APEX_URL="https://<your-adb-name>.adb.<region>.oraclecloudapps.com/ords/apex"
    fi
else
    print_warning "Could not retrieve database information"
    APEX_URL="https://<your-adb-name>.adb.<region>.oraclecloudapps.com/ords/apex"
fi

################################################################################
# Step 7: Create Sample Data (Optional)
################################################################################

echo ""
read -p "Do you want to insert sample data for testing? (y/n): " INSERT_SAMPLE

if [ "$INSERT_SAMPLE" = "y" ] || [ "$INSERT_SAMPLE" = "Y" ]; then
    print_info "Inserting sample data..."
    
    cat > /tmp/sample_data.sql << 'EOF'
-- Insert sample congress members
INSERT INTO congress_members (member_id, first_name, last_name, party, state, chamber)
VALUES ('P000197', 'Nancy', 'Pelosi', 'Democrat', 'CA', 'House');

INSERT INTO congress_members (member_id, first_name, last_name, party, state, chamber)
VALUES ('M000303', 'John', 'McCain', 'Republican', 'AZ', 'Senate');

INSERT INTO congress_members (member_id, first_name, last_name, party, state, chamber)
VALUES ('W000817', 'Elizabeth', 'Warren', 'Democrat', 'MA', 'Senate');

-- Insert sample trades
INSERT INTO stock_trades (member_id, ticker, transaction_date, disclosure_date, transaction_type, amount_range, asset_description)
VALUES ('P000197', 'AAPL', SYSDATE - 15, SYSDATE - 10, 'Purchase', '$15,001 - $50,000', 'Apple Inc.');

INSERT INTO stock_trades (member_id, ticker, transaction_date, disclosure_date, transaction_type, amount_range, asset_description)
VALUES ('M000303', 'MSFT', SYSDATE - 12, SYSDATE - 8, 'Purchase', '$50,001 - $100,000', 'Microsoft Corporation');

INSERT INTO stock_trades (member_id, ticker, transaction_date, disclosure_date, transaction_type, amount_range, asset_description)
VALUES ('W000817', 'GOOGL', SYSDATE - 10, SYSDATE - 5, 'Purchase', '$1,001 - $15,000', 'Alphabet Inc.');

-- Insert sample stock prices
INSERT INTO stock_prices (ticker, price_date, open_price, high_price, low_price, close_price, volume)
VALUES ('AAPL', SYSDATE - 15, 175.50, 178.20, 174.80, 177.30, 58000000);

INSERT INTO stock_prices (ticker, price_date, open_price, high_price, low_price, close_price, volume)
VALUES ('AAPL', SYSDATE, 177.00, 179.50, 176.50, 178.90, 52000000);

INSERT INTO stock_prices (ticker, price_date, open_price, high_price, low_price, close_price, volume)
VALUES ('MSFT', SYSDATE - 12, 380.20, 385.40, 379.50, 383.10, 32000000);

INSERT INTO stock_prices (ticker, price_date, open_price, high_price, low_price, close_price, volume)
VALUES ('MSFT', SYSDATE, 382.50, 387.20, 381.80, 385.60, 30000000);

INSERT INTO stock_prices (ticker, price_date, open_price, high_price, low_price, close_price, volume)
VALUES ('GOOGL', SYSDATE - 10, 140.30, 142.80, 139.90, 141.70, 28000000);

INSERT INTO stock_prices (ticker, price_date, open_price, high_price, low_price, close_price, volume)
VALUES ('GOOGL', SYSDATE, 141.50, 143.20, 140.80, 142.30, 26000000);

COMMIT;

-- Refresh opportunities
BEGIN
    congress_tracker_pkg.refresh_opportunities();
END;
/
EOF
    
    $SQLCL -cloudconfig "$WALLET_DIR/wallet.zip" "admin/${ADMIN_PASSWORD}@${DB_SERVICE}" @/tmp/sample_data.sql
    
    if [ $? -eq 0 ]; then
        print_success "Sample data inserted successfully"
    else
        print_warning "Failed to insert sample data"
    fi
fi

################################################################################
# Step 8: Create Configuration File
################################################################################

echo ""
print_info "Creating configuration file..."

CONFIG_FILE="${HOME}/congress_tracker_config.txt"

cat > "$CONFIG_FILE" << EOF
╔═══════════════════════════════════════════════════════════════════════╗
║         Congressional Stock Tracker - Configuration                  ║
╚═══════════════════════════════════════════════════════════════════════╝

Deployment Date: $(date)

Database Information:
--------------------
Database OCID: $ADB_OCID
Database Name: $DB_NAME
Connection Service: $DB_SERVICE
Wallet Location: $WALLET_DIR

APEX Information:
-----------------
APEX URL: $APEX_URL
Workspace: $WORKSPACE_NAME
Username: $WORKSPACE_ADMIN
Password: <saved securely>

Connection String:
------------------
For SQLcl: 
  sql -cloudconfig ${WALLET_DIR}/wallet.zip admin/<password>@${DB_SERVICE}

Next Steps:
-----------
1. Access APEX at: $APEX_URL
2. Login with:
   - Workspace: $WORKSPACE_NAME
   - Username: $WORKSPACE_ADMIN
   - Password: (the one you set during deployment)

3. Create APEX Application:
   - Click "App Builder"
   - Click "Create" > "New Application"
   - Name: "Congressional Stock Tracker"
   - Add pages for Dashboard, Opportunities, Trades, Members, Alerts

4. Set up REST APIs:
   - Go to SQL Workshop > RESTful Services
   - Create module with base path /congress/
   - Add handlers for opportunities, trades, members

5. Configure Data Loading:
   - Use APEX_WEB_SERVICE to fetch congressional trade data
   - Schedule jobs to refresh data periodically

Important Files:
----------------
- This config file: $CONFIG_FILE
- Database wallet: $WALLET_DIR/wallet.zip
- Schema script: /tmp/init_schema.sql

To Update Schema:
-----------------
$SQLCL -cloudconfig ${WALLET_DIR}/wallet.zip admin/<password>@${DB_SERVICE}

╔═══════════════════════════════════════════════════════════════════════╗
║                      Deployment Complete!                             ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF

print_success "Configuration saved to: $CONFIG_FILE"

################################################################################
# Step 9: Summary
################################################################################

echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Successful!                             ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
print_success "Database schema created"
print_success "APEX workspace created"
print_success "Views and packages deployed"
print_success "Scheduler job configured"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  APEX Access Information"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "  URL:       $APEX_URL"
echo "  Workspace: $WORKSPACE_NAME"
echo "  Username:  $WORKSPACE_ADMIN"
echo "  Password:  <as configured>"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
print_info "Full configuration saved to: $CONFIG_FILE"
print_info "Wallet location: $WALLET_DIR"
echo ""
print_info "Next steps:"
echo "  1. Open APEX URL in your browser"
echo "  2. Log in with your credentials"
echo "  3. Create the APEX application using App Builder"
echo "  4. Import pages and configure REST services"
echo ""
print_info "To connect with SQLcl later:"
echo "  $SQLCL -cloudconfig ${WALLET_DIR}/wallet.zip admin/<password>@${DB_SERVICE}"
echo ""
print_success "Deployment complete! 🚀"
echo ""

# Cleanup temporary files
rm -f /tmp/init_schema.sql /tmp/create_workspace.sql /tmp/sample_data.sql

exit 0