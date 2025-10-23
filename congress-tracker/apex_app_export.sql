prompt --application/set_environment
set define off verify off feedback off
whenever sqlerror then exit sql.sqlcode rollback
--------------------------------------------------------------------------------
--
-- Congressional Stock Tracker APEX Application
-- Application ID: 100
-- 
-- Import Instructions:
-- 1. Login to APEX as CONGRESS_ADMIN
-- 2. Go to App Builder
-- 3. Click Import
-- 4. Upload this file
-- 5. Click Next, Next, Install Application
--
--------------------------------------------------------------------------------

begin
  -- Set workspace
  apex_application_install.set_workspace('CONGRESS_TRACKER');
  apex_application_install.set_schema('CONGRESS_SCHEMA');
  apex_application_install.set_application_id(100);
  apex_application_install.set_application_name('Congressional Stock Tracker');
  apex_application_install.set_application_alias('CONGRESS_TRACKER');
  apex_application_install.generate_offset;
  apex_application_install.generate_application_id;
end;
/

prompt --application/shared_components/navigation/lists/desktop_navigation_menu
begin
wwv_flow_api.create_list(
  p_id=> wwv_flow_api.id(1001)
 ,p_name=> 'Desktop Navigation Menu'
 ,p_list_status=> 'PUBLIC'
);

wwv_flow_api.create_list_item(
  p_id=> wwv_flow_api.id(1002)
 ,p_list_item_display_sequence=> 10
 ,p_list_item_link_text=> 'Home'
 ,p_list_item_link_target=> 'f?p=&APP_ID.:1:&SESSION.::&DEBUG.:::'
 ,p_list_item_icon=> 'fa-home'
 ,p_list_item_current_type=> 'TARGET_PAGE'
);

wwv_flow_api.create_list_item(
  p_id=> wwv_flow_api.id(1003)
 ,p_list_item_display_sequence=> 20
 ,p_list_item_link_text=> 'Opportunities'
 ,p_list_item_link_target=> 'f?p=&APP_ID.:2:&SESSION.::&DEBUG.:::'
 ,p_list_item_icon=> 'fa-star'
 ,p_list_item_current_type=> 'TARGET_PAGE'
);

wwv_flow_api.create_list_item(
  p_id=> wwv_flow_api.id(1004)
 ,p_list_item_display_sequence=> 30
 ,p_list_item_link_text=> 'Recent Trades'
 ,p_list_item_link_target=> 'f?p=&APP_ID.:3:&SESSION.::&DEBUG.:::'
 ,p_list_item_icon=> 'fa-exchange'
 ,p_list_item_current_type=> 'TARGET_PAGE'
);

wwv_flow_api.create_list_item(
  p_id=> wwv_flow_api.id(1005)
 ,p_list_item_display_sequence=> 40
 ,p_list_item_link_text=> 'Members'
 ,p_list_item_link_target=> 'f?p=&APP_ID.:4:&SESSION.::&DEBUG.:::'
 ,p_list_item_icon=> 'fa-users'
 ,p_list_item_current_type=> 'TARGET_PAGE'
);

wwv_flow_api.create_list_item(
  p_id=> wwv_flow_api.id(1006)
 ,p_list_item_display_sequence=> 50
 ,p_list_item_link_text=> 'Alerts'
 ,p_list_item_link_target=> 'f?p=&APP_ID.:6:&SESSION.::&DEBUG.:::'
 ,p_list_item_icon=> 'fa-bell'
 ,p_list_item_current_type=> 'TARGET_PAGE'
);

wwv_flow_api.create_list_item(
  p_id=> wwv_flow_api.id(1007)
 ,p_list_item_display_sequence=> 60
 ,p_list_item_link_text=> 'Admin'
 ,p_list_item_link_target=> 'f?p=&APP_ID.:7:&SESSION.::&DEBUG.:::'
 ,p_list_item_icon=> 'fa-cog'
 ,p_list_item_current_type=> 'TARGET_PAGE'
);

end;
/

prompt --application/pages/page_00001
begin
wwv_flow_api.create_page(
  p_id=> 1
 ,p_user_interface_id=> wwv_flow_api.id(1)
 ,p_name=> 'Dashboard'
 ,p_alias=> 'HOME'
 ,p_step_title=> 'Congressional Stock Tracker'
 ,p_autocomplete_on_off=> 'OFF'
 ,p_page_template_options=> '#DEFAULT#'
 ,p_protection_level=> 'C'
 ,p_last_updated_by=> 'CONGRESS_ADMIN'
 ,p_last_upd_yyyymmddhh24miss=> '20251022000000'
);

-- Dashboard Regions
wwv_flow_api.create_page_plug(
  p_id=> wwv_flow_api.id(2001)
 ,p_plug_name=> 'Quick Stats'
 ,p_region_template_options=> '#DEFAULT#:t-Region--scrollBody'
 ,p_plug_template=> wwv_flow_api.id(1)
 ,p_plug_display_sequence=> 10
 ,p_plug_display_point=> 'BODY'
 ,p_query_type=> 'SQL'
 ,p_plug_source=> q'~
SELECT 
    (SELECT COUNT(*) FROM congress_members) as total_members,
    (SELECT COUNT(*) FROM investment_opportunities WHERE opportunity_score >= 60) as hot_opportunities,
    (SELECT COUNT(*) FROM stock_trades WHERE transaction_date >= TRUNC(SYSDATE, 'MM')) as trades_this_month
FROM DUAL
~'
 ,p_plug_source_type=> 'NATIVE_SQL_REPORT'
 ,p_plug_query_options=> 'DERIVED_REPORT_COLUMNS'
);

wwv_flow_api.create_page_plug(
  p_id=> wwv_flow_api.id(2002)
 ,p_plug_name=> 'Top Opportunities'
 ,p_region_template_options=> '#DEFAULT#'
 ,p_plug_template=> wwv_flow_api.id(1)
 ,p_plug_display_sequence=> 20
 ,p_plug_display_point=> 'BODY'
 ,p_query_type=> 'SQL'
 ,p_plug_source=> q'~
SELECT 
    ticker,
    company_name,
    opportunity_score,
    current_price,
    price_change_pct,
    num_purchases,
    num_members,
    priority_level
FROM v_top_opportunities
WHERE ROWNUM <= 10
ORDER BY opportunity_score DESC
~'
 ,p_plug_source_type=> 'NATIVE_IR'
 ,p_plug_query_options=> 'DERIVED_REPORT_COLUMNS'
);

end;
/

prompt --application/pages/page_00002
begin
wwv_flow_api.create_page(
  p_id=> 2
 ,p_user_interface_id=> wwv_flow_api.id(1)
 ,p_name=> 'Investment Opportunities'
 ,p_alias=> 'OPPORTUNITIES'
 ,p_step_title=> 'Investment Opportunities'
 ,p_autocomplete_on_off=> 'OFF'
 ,p_page_template_options=> '#DEFAULT#'
 ,p_protection_level=> 'C'
 ,p_last_updated_by=> 'CONGRESS_ADMIN'
 ,p_last_upd_yyyymmddhh24miss=> '20251022000000'
);

wwv_flow_api.create_page_plug(
  p_id=> wwv_flow_api.id(3001)
 ,p_plug_name=> 'Investment Opportunities'
 ,p_region_template_options=> '#DEFAULT#'
 ,p_plug_template=> wwv_flow_api.id(1)
 ,p_plug_display_sequence=> 10
 ,p_plug_display_point=> 'BODY'
 ,p_query_type=> 'SQL'
 ,p_plug_source=> q'~
SELECT 
    ticker,
    company_name,
    opportunity_score,
    current_price,
    trade_disclosure_price,
    price_change_pct,
    num_purchases,
    num_members,
    priority_level,
    trade_date
FROM v_top_opportunities
ORDER BY opportunity_score DESC
~'
 ,p_plug_source_type=> 'NATIVE_IR'
 ,p_plug_query_options=> 'DERIVED_REPORT_COLUMNS'
);

end;
/

prompt --application/pages/page_00003
begin
wwv_flow_api.create_page(
  p_id=> 3
 ,p_user_interface_id=> wwv_flow_api.id(1)
 ,p_name=> 'Recent Trades'
 ,p_alias=> 'TRADES'
 ,p_step_title=> 'Recent Trades'
 ,p_autocomplete_on_off=> 'OFF'
 ,p_page_template_options=> '#DEFAULT#'
 ,p_protection_level=> 'C'
 ,p_last_updated_by=> 'CONGRESS_ADMIN'
 ,p_last_upd_yyyymmddhh24miss=> '20251022000000'
);

wwv_flow_api.create_page_plug(
  p_id=> wwv_flow_api.id(4001)
 ,p_plug_name=> 'Recent Congressional Trades'
 ,p_region_template_options=> '#DEFAULT#'
 ,p_plug_template=> wwv_flow_api.id(1)
 ,p_plug_display_sequence=> 10
 ,p_plug_display_point=> 'BODY'
 ,p_query_type=> 'SQL'
 ,p_plug_source=> q'~
SELECT 
    ticker,
    member_name,
    party,
    state,
    chamber,
    transaction_type,
    transaction_date,
    disclosure_date,
    amount_range,
    price_at_trade,
    current_price,
    price_change_pct
FROM v_recent_trades
WHERE ROWNUM <= 500
ORDER BY transaction_date DESC
~'
 ,p_plug_source_type=> 'NATIVE_IR'
 ,p_plug_query_options=> 'DERIVED_REPORT_COLUMNS'
);

end;
/

prompt --application/pages/page_00004
begin
wwv_flow_api.create_page(
  p_id=> 4
 ,p_user_interface_id=> wwv_flow_api.id(1)
 ,p_name=> 'Member Analysis'
 ,p_alias=> 'MEMBERS'
 ,p_step_title=> 'Member Analysis'
 ,p_autocomplete_on_off=> 'OFF'
 ,p_page_template_options=> '#DEFAULT#'
 ,p_protection_level=> 'C'
 ,p_last_updated_by=> 'CONGRESS_ADMIN'
 ,p_last_upd_yyyymmddhh24miss=> '20251022000000'
);

wwv_flow_api.create_page_plug(
  p_id=> wwv_flow_api.id(5001)
 ,p_plug_name=> 'Congressional Members Trading Activity'
 ,p_region_template_options=> '#DEFAULT#'
 ,p_plug_template=> wwv_flow_api.id(1)
 ,p_plug_display_sequence=> 10
 ,p_plug_display_point=> 'BODY'
 ,p_query_type=> 'SQL'
 ,p_plug_source=> q'~
SELECT 
    member_name,
    party,
    state,
    chamber,
    unique_tickers_traded,
    total_trades,
    purchases,
    sales,
    last_trade_date
FROM v_member_trading_activity
ORDER BY total_trades DESC
~'
 ,p_plug_source_type=> 'NATIVE_IR'
 ,p_plug_query_options=> 'DERIVED_REPORT_COLUMNS'
);

end;
/

prompt --application/pages/page_00006
begin
wwv_flow_api.create_page(
  p_id=> 6
 ,p_user_interface_id=> wwv_flow_api.id(1)
 ,p_name=> 'Alerts'
 ,p_alias=> 'ALERTS'
 ,p_step_title=> 'Trade Alerts'
 ,p_autocomplete_on_off=> 'OFF'
 ,p_page_template_options=> '#DEFAULT#'
 ,p_protection_level=> 'C'
 ,p_last_updated_by=> 'CONGRESS_ADMIN'
 ,p_last_upd_yyyymmddhh24miss=> '20251022000000'
);

wwv_flow_api.create_page_plug(
  p_id=> wwv_flow_api.id(6001)
 ,p_plug_name=> 'Trade Alerts'
 ,p_region_template_options=> '#DEFAULT#'
 ,p_plug_template=> wwv_flow_api.id(1)
 ,p_plug_display_sequence=> 10
 ,p_plug_display_point=> 'BODY'
 ,p_query_type=> 'SQL'
 ,p_plug_source=> q'~
SELECT 
    alert_id,
    ticker,
    alert_type,
    alert_message,
    is_read,
    created_at
FROM trade_alerts
ORDER BY created_at DESC
~'
 ,p_plug_source_type=> 'NATIVE_IR'
 ,p_plug_query_options=> 'DERIVED_REPORT_COLUMNS'
);

end;
/

prompt --application/pages/page_00007
begin
wwv_flow_api.create_page(
  p_id=> 7
 ,p_user_interface_id=> wwv_flow_api.id(1)
 ,p_name=> 'Admin Panel'
 ,p_alias=> 'ADMIN'
 ,p_step_title=> 'Admin Panel'
 ,p_autocomplete_on_off=> 'OFF'
 ,p_page_template_options=> '#DEFAULT#'
 ,p_protection_level=> 'C'
 ,p_last_updated_by=> 'CONGRESS_ADMIN'
 ,p_last_upd_yyyymmddhh24miss=> '20251022000000'
);

wwv_flow_api.create_page_plug(
  p_id=> wwv_flow_api.id(7001)
 ,p_plug_name=> 'System Status'
 ,p_region_template_options=> '#DEFAULT#'
 ,p_plug_template=> wwv_flow_api.id(1)
 ,p_plug_display_sequence=> 10
 ,p_plug_display_point=> 'BODY'
 ,p_query_type=> 'SQL'
 ,p_plug_source=> q'~
SELECT 
    'Total Members' as metric,
    TO_CHAR(COUNT(*)) as value
FROM congress_members
UNION ALL
SELECT 
    'Total Trades' as metric,
    TO_CHAR(COUNT(*)) as value
FROM stock_trades
UNION ALL
SELECT 
    'Active Opportunities' as metric,
    TO_CHAR(COUNT(*)) as value
FROM investment_opportunities
WHERE opportunity_score >= 60
UNION ALL
SELECT 
    'Last Trade Date' as metric,
    TO_CHAR(MAX(transaction_date), 'DD-MON-YYYY') as value
FROM stock_trades
~'
 ,p_plug_source_type=> 'NATIVE_SQL_REPORT'
 ,p_plug_query_options=> 'DERIVED_REPORT_COLUMNS'
);

-- Add Refresh Button
wwv_flow_api.create_page_button(
  p_id=> wwv_flow_api.id(7002)
 ,p_button_sequence=> 10
 ,p_button_plug_id=> wwv_flow_api.id(7001)
 ,p_button_name=> 'REFRESH_OPPORTUNITIES'
 ,p_button_action=> 'SUBMIT'
 ,p_button_template_options=> '#DEFAULT#'
 ,p_button_template_id=> wwv_flow_api.id(1)
 ,p_button_image_alt=> 'Refresh Opportunities'
 ,p_button_position=> 'REGION_TEMPLATE_CREATE'
);

-- Add Process for Refresh Button
wwv_flow_api.create_page_process(
  p_id=> wwv_flow_api.id(7003)
 ,p_process_sequence=> 10
 ,p_process_point=> 'AFTER_SUBMIT'
 ,p_process_type=> 'NATIVE_PLSQL'
 ,p_process_name=> 'Refresh Opportunities'
 ,p_process_sql_clob=> 'BEGIN congress_tracker_pkg.refresh_opportunities; END;'
 ,p_process_when_button_id=> wwv_flow_api.id(7002)
);

end;
/

prompt --application/end_environment
begin
  commit;
  wwv_flow_api.import_end(p_auto_install_sup_obj => nvl(wwv_flow_application_install.get_auto_install_sup_obj, false));
end;
/

prompt Application "Congressional Stock Tracker" import complete.
