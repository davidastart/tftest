# Agents You Can Trust

## Introduction

You've built a memory core that stores facts and finds them by meaning. But there's a critical piece missing for production use: **accountability**.

Agentic memory isn't just about remembering facts—it's about making decisions, taking actions, and being accountable for the outcomes. Some of those decisions are too important to delegate entirely to an AI. An expense over $500? A customer refund? A policy exception? These need human judgment.

In this lab, you'll add **human-in-the-loop** approval workflows to your agent. The agent will pause and wait for your approval before proceeding with important actions. You'll build a complete expense processing system and use built-in audit trails to see everything your agent does.

This isn't simulated—the agent will actually stop and wait for you to approve.

This is what separates AI experiments from real transformation: agents that know when to ask for help and can prove what they did.

Estimated Time: 25 minutes

### Objectives

* Create an expense workflow combining relational constraints with JSON flexibility
* Enable human-in-the-loop approval using `enable_human_tool`
* Build a complete expense submission and approval workflow
* Use built-in history views for observability and audit
* Complete your understanding of how agentic memory enables real business outcomes

### Prerequisites

This lab assumes you have:

* Completed Lab 1 and Lab 2 (or run the quick setup below)
* Oracle Database 26ai with Select AI Agent
* Basic knowledge of SQL and PL/SQL

## Task 1: Quick Setup (If Starting Fresh)

If you completed Labs 1 and 2, skip to Task 2. Otherwise, run this setup to create the foundation objects you need—the memory core, rules engine, and embedding model from the previous labs.

1. Create the profile. This establishes the connection to your LLM provider that the agent will use for all AI interactions.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI.CREATE_PROFILE(
            profile_name => 'AGENT_PROFILE',
            attributes   => JSON_OBJECT(
                'provider'         VALUE 'oci',
                'credential_name'  VALUE 'OCI_CRED',
                'model'            VALUE 'cohere.command-r-plus',
                'oci_compartment_id' VALUE 'ocid1.compartment.oc1..your_compartment'
            )
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    /
    </copy>
    ```

2. Create the memory core table with JSON and vectors. This table stores agent memories with both flexible JSON content and semantic embeddings for intelligent retrieval—the foundation of agentic memory.

    ```sql
    <copy>
    CREATE TABLE agent_memory (
        memory_id      RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
        memory_type    VARCHAR2(20) DEFAULT 'FACT',
        content        JSON NOT NULL,
        embedding      VECTOR(384),
        created_at     TIMESTAMP DEFAULT SYSTIMESTAMP
    );
    </copy>
    ```

3. Create rules table with JSON config. Business rules stored as JSON allow flexible condition/action definitions without schema changes.

    ```sql
    <copy>
    CREATE TABLE agent_rules (
        rule_id        RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
        rule_name      VARCHAR2(200) NOT NULL,
        rule_config    JSON NOT NULL,
        priority       NUMBER DEFAULT 100,
        is_active      NUMBER(1) DEFAULT 1
    );

    INSERT INTO agent_rules (rule_name, rule_config, priority) VALUES (
        'Auto-approve small', 
        '{"condition":{"field":"amount","operator":"lt","value":100},"action":"AUTO_APPROVE"}',
        100);
    INSERT INTO agent_rules (rule_name, rule_config, priority) VALUES (
        'Manager approval medium',
        '{"condition":{"field":"amount","operator":"between","min":100,"max":500},"action":"REQUIRE_APPROVAL"}',
        90);
    INSERT INTO agent_rules (rule_name, rule_config, priority) VALUES (
        'Director approval large',
        '{"condition":{"field":"amount","operator":"gte","value":500},"action":"REQUIRE_APPROVAL"}',
        80);
    COMMIT;
    </copy>
    ```

4. Load ONNX model. This imports the embedding model that enables semantic search capabilities.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD.GET_OBJECT(
            credential_name => NULL,
            directory_name  => 'DATA_PUMP_DIR',
            object_uri      => 'https://adwc4pm.objectstorage.us-ashburn-1.oci.customer-oci.com/p/eLddQappgBJ7jNi6Guz9m9LOtYe2u8LWY19GfgU8flFK4N9YgP4kTlrE9Px3pE12/n/adwc4pm/b/OML-Resources/o/all_MiniLM_L12_v2.onnx'
        );
        DBMS_VECTOR.LOAD_ONNX_MODEL('DATA_PUMP_DIR', 'all_MiniLM_L12_v2.onnx', 'ALL_MINILM_L12_V2');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    /
    </copy>
    ```

## Task 2: Create the Expense Table

The expense table demonstrates Oracle's converged approach—combining relational columns for structure and constraints with JSON for flexible metadata. This design gives you the best of both worlds: enforced data integrity for critical fields and schema-free flexibility for additional details.

This is agentic memory applied to workflow state: the agent needs to track what's pending, what's approved, and who made each decision.

1. Create the expense table. The `status` column uses a CHECK constraint to ensure only valid values are stored, while the `details` JSON column can hold any additional information without predefined structure.

    ```sql
    <copy>
    CREATE TABLE expenses (
        expense_id     RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
        employee_name  VARCHAR2(100) NOT NULL,
        amount         NUMBER(10,2) NOT NULL,
        status         VARCHAR2(20) DEFAULT 'PENDING'
                       CONSTRAINT chk_status CHECK (status IN ('PENDING','APPROVED','REJECTED')),
        details        JSON,
        submitted_at   TIMESTAMP DEFAULT SYSTIMESTAMP,
        decided_at     TIMESTAMP,
        decided_by     VARCHAR2(100)
    );
    </copy>
    ```

2. Create indexes for common query patterns. These indexes speed up the most frequent operations: finding pending expenses and looking up expenses by employee.

    ```sql
    <copy>
    CREATE INDEX idx_expense_status ON expenses(status);
    CREATE INDEX idx_expense_employee ON expenses(employee_name);
    </copy>
    ```

    >**Note:** The design uses NUMBER for amount (enabling math operations and rule comparisons), VARCHAR2 + CHECK for status (constraining to valid values), and JSON for details (storing category, description, receipts, notes—anything the workflow needs).

## Task 3: Create Expense Functions

These functions implement the expense workflow logic. Each function handles a specific action and returns a clear message indicating what happened. The `PRAGMA AUTONOMOUS_TRANSACTION` allows these functions to commit their own changes even when called from within a query.

1. Create the submit expense function. This function creates the expense record, then checks business rules to determine if it can be auto-approved or needs human approval. The result message tells the agent (and user) what happened.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION submit_expense(
        p_employee    VARCHAR2,
        p_amount      NUMBER,
        p_category    VARCHAR2,
        p_description VARCHAR2
    ) RETURN VARCHAR2 AS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_expense_id  RAW(16);
        v_action      VARCHAR2(100);
        v_rule_name   VARCHAR2(200);
    BEGIN
        INSERT INTO expenses (employee_name, amount, status, details)
        VALUES (
            p_employee, 
            p_amount, 
            'PENDING', 
            JSON_OBJECT(
                'category'    VALUE p_category,
                'description' VALUE p_description,
                'submitted'   VALUE TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS'),
                'source'      VALUE 'agent'
            )
        )
        RETURNING expense_id INTO v_expense_id;
        COMMIT;
        
        BEGIN
            SELECT action, rule_name INTO v_action, v_rule_name
            FROM (
                SELECT 
                    JSON_VALUE(rule_config, '$.action') as action,
                    rule_name
                FROM agent_rules
                WHERE is_active = 1
                AND JSON_VALUE(rule_config, '$.condition.field') = 'amount'
                AND (
                    (JSON_VALUE(rule_config, '$.condition.operator') = 'lt' 
                     AND p_amount < JSON_VALUE(rule_config, '$.condition.value' RETURNING NUMBER))
                    OR
                    (JSON_VALUE(rule_config, '$.condition.operator') = 'gte' 
                     AND p_amount >= JSON_VALUE(rule_config, '$.condition.value' RETURNING NUMBER))
                    OR
                    (JSON_VALUE(rule_config, '$.condition.operator') = 'between' 
                     AND p_amount >= JSON_VALUE(rule_config, '$.condition.min' RETURNING NUMBER)
                     AND p_amount < JSON_VALUE(rule_config, '$.condition.max' RETURNING NUMBER))
                )
                ORDER BY priority DESC
            ) WHERE ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_action := 'AUTO_APPROVE';
                v_rule_name := 'Default';
        END;
        
        IF v_action = 'AUTO_APPROVE' THEN
            UPDATE expenses 
            SET status = 'APPROVED', decided_by = 'SYSTEM', decided_at = SYSTIMESTAMP
            WHERE expense_id = v_expense_id;
            COMMIT;
            RETURN 'Expense AUTO-APPROVED. ID: ' || RAWTOHEX(v_expense_id) || 
                   '. Amount $' || p_amount || ' is within auto-approval threshold.';
        ELSE
            RETURN 'Expense PENDING APPROVAL. ID: ' || RAWTOHEX(v_expense_id) ||
                   '. Amount $' || p_amount || ' requires approval per rule: ' || v_rule_name ||
                   '. Please confirm you want to approve this expense.';
        END IF;
    END;
    /
    </copy>
    ```

2. Create the approve expense function. This function updates the expense status and uses `JSON_MERGEPATCH` to add approval details to the existing JSON without overwriting other fields—preserving the original submission data while adding audit information.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION approve_expense(
        p_expense_id VARCHAR2,
        p_approver   VARCHAR2
    ) RETURN VARCHAR2 AS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_id       RAW(16);
        v_amount   NUMBER;
        v_employee VARCHAR2(100);
    BEGIN
        v_id := HEXTORAW(p_expense_id);
        
        SELECT amount, employee_name
        INTO v_amount, v_employee
        FROM expenses WHERE expense_id = v_id;
        
        UPDATE expenses 
        SET status = 'APPROVED', 
            decided_by = p_approver, 
            decided_at = SYSTIMESTAMP,
            details = JSON_MERGEPATCH(details, JSON_OBJECT(
                'approved_by' VALUE p_approver,
                'approved_at' VALUE TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')
            ))
        WHERE expense_id = v_id AND status = 'PENDING';
        
        IF SQL%ROWCOUNT = 0 THEN
            RETURN 'Expense not found or already processed.';
        END IF;
        
        COMMIT;
        RETURN 'APPROVED: $' || v_amount || ' expense for ' || v_employee || ' approved by ' || p_approver;
    END;
    /
    </copy>
    ```

    >**Note:** `JSON_MERGEPATCH` updates the JSON details without losing existing fields. The relational columns track status changes while JSON stores the complete audit trail.

3. Create the reject expense function. Similar to approval, this captures the rejection reason in the JSON details for audit purposes while updating the relational status field.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION reject_expense(
        p_expense_id VARCHAR2,
        p_reason     VARCHAR2
    ) RETURN VARCHAR2 AS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_id RAW(16);
    BEGIN
        v_id := HEXTORAW(p_expense_id);
        
        UPDATE expenses 
        SET status = 'REJECTED', 
            decided_by = 'REJECTED', 
            decided_at = SYSTIMESTAMP,
            details = JSON_MERGEPATCH(details, JSON_OBJECT(
                'rejection_reason' VALUE p_reason,
                'rejected_at' VALUE TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')
            ))
        WHERE expense_id = v_id AND status = 'PENDING';
        
        IF SQL%ROWCOUNT = 0 THEN
            RETURN 'Expense not found or already processed.';
        END IF;
        
        COMMIT;
        RETURN 'Expense REJECTED. Reason: ' || p_reason;
    END;
    /
    </copy>
    ```

4. Create the list pending expenses function. This function provides a formatted view of all expenses awaiting approval, combining relational fields with JSON details into a human-readable summary.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION list_pending_expenses RETURN CLOB AS
        v_result CLOB := '';
        v_count NUMBER := 0;
    BEGIN
        FOR rec IN (
            SELECT 
                RAWTOHEX(expense_id) as id, 
                employee_name, 
                amount, 
                JSON_VALUE(details, '$.category') as category,
                JSON_VALUE(details, '$.description') as description,
                TO_CHAR(submitted_at, 'YYYY-MM-DD HH24:MI') as submitted
            FROM expenses
            WHERE status = 'PENDING'
            ORDER BY submitted_at
        ) LOOP
            v_result := v_result || '- ID: ' || rec.id || CHR(10);
            v_result := v_result || '  Employee: ' || rec.employee_name || CHR(10);
            v_result := v_result || '  Amount: $' || rec.amount || ' (' || NVL(rec.category, 'general') || ')' || CHR(10);
            v_result := v_result || '  Description: ' || NVL(rec.description, 'N/A') || CHR(10);
            v_result := v_result || '  Submitted: ' || rec.submitted || CHR(10) || CHR(10);
            v_count := v_count + 1;
        END LOOP;
        
        IF v_count = 0 THEN
            RETURN 'No pending expenses.';
        END IF;
        
        RETURN 'Found ' || v_count || ' pending expense(s):' || CHR(10) || CHR(10) || v_result;
    END;
    /
    </copy>
    ```

## Task 4: Register Expense Tools

Each tool registration teaches the agent about a specific capability. The instruction text is critical—it guides the LLM on when to use the tool and how to format the parameters. Clear, specific instructions lead to more reliable agent behavior.

1. Register the submit expense tool. The instruction specifies exactly what parameters are needed and what format they should be in, reducing errors from the LLM.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'SUBMIT_EXPENSE_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Submit an expense for processing. Returns whether it was auto-approved or needs manager approval. ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_EMPLOYEE (name), P_AMOUNT (dollar amount), P_CATEGORY (meals, travel, supplies, entertainment), ' ||
                                    'P_DESCRIPTION (what the expense was for).',
                'function'    VALUE 'submit_expense'
            ),
            description => 'Submits expense and determines approval needs'
        );
    END;
    /
    </copy>
    ```

2. Register the approve expense tool. The instruction emphasizes that this should only be called after human confirmation—this helps the agent understand the workflow sequence.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'APPROVE_EXPENSE_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Approve a pending expense. Only use after human confirms approval. ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_EXPENSE_ID (the expense ID to approve), P_APPROVER (name of person approving).',
                'function'    VALUE 'approve_expense'
            ),
            description => 'Approves a pending expense'
        );
    END;
    /
    </copy>
    ```

3. Register the reject expense tool. Similar to approval, this instruction makes clear that human confirmation is required before rejection.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'REJECT_EXPENSE_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Reject a pending expense. Only use after human confirms rejection. ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_EXPENSE_ID (the expense ID to reject), P_REASON (why it was rejected).',
                'function'    VALUE 'reject_expense'
            ),
            description => 'Rejects a pending expense'
        );
    END;
    /
    </copy>
    ```

4. Register the list pending tool. This simple tool has no parameters—it just returns the current queue of pending expenses.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'LIST_PENDING_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'List all expenses waiting for approval. Use this to see what needs attention.',
                'function'    VALUE 'list_pending_expenses'
            ),
            description => 'Lists pending expenses'
        );
    END;
    /
    </copy>
    ```

## Task 5: Create the Expense Agent with Human Approval

Here's where we enable human-in-the-loop capability—the key to building agents you can trust. The `enable_human_tool` attribute allows the agent to pause execution and request human input. This is essential for workflows where certain decisions require human judgment or approval.

Without this capability, agents either auto-approve everything (risky) or require human review of everything (defeats the purpose). Human-in-the-loop lets you define the boundary: routine decisions proceed automatically, while important decisions pause for human judgment.

1. Clean up previous agents. We remove any existing agent components to start fresh with our expense-focused configuration.

    ```sql
    <copy>
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TEAM('SMART_TEAM', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TEAM('EXPENSE_TEAM', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TASK('SMART_TASK', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TASK('EXPENSE_TASK', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_AGENT('SMART_AGENT', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_AGENT('EXPENSE_AGENT', TRUE); END;
    /
    </copy>
    ```

2. Create expense agent. The role emphasizes strict rule following and the requirement for human confirmation on approval decisions—shaping the agent's behavior to be cautious about taking irreversible actions.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
            agent_name  => 'EXPENSE_AGENT',
            attributes  => JSON_OBJECT(
                'profile_name' VALUE 'AGENT_PROFILE',
                'role'         VALUE 'You are an expense processing agent. You help employees submit expenses and ' ||
                                     'help managers review and approve them. You follow company rules strictly. ' ||
                                     'For expenses requiring approval, you MUST ask the human for explicit ' ||
                                     'confirmation before approving. Never approve expenses over $100 without human confirmation.'
            ),
            description => 'Expense processing with human approval'
        );
    END;
    /
    </copy>
    ```

3. Create task with human-in-the-loop enabled. The `enable_human_tool` attribute is the key—it activates the agent's ability to pause and request human input when needed.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TASK(
            task_name   => 'EXPENSE_TASK',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Process this expense request:' || CHR(10) ||
                                    '1. To submit expense: call SUBMIT_EXPENSE_TOOL once.' || CHR(10) ||
                                    '2. If approval needed (>=$100): ask the human for confirmation, then call APPROVE or REJECT once.' || CHR(10) ||
                                    '3. To list pending: call LIST_PENDING_TOOL once.' || CHR(10) ||
                                    'After completing the action, provide your final response. Do not continue calling tools.' || CHR(10) ||
                                    'User request: {query}',
                'tools'       VALUE JSON_ARRAY(
                    'SUBMIT_EXPENSE_TOOL', 
                    'APPROVE_EXPENSE_TOOL', 
                    'REJECT_EXPENSE_TOOL', 
                    'LIST_PENDING_TOOL'
                ),
                'enable_human_tool' VALUE 'true'
            ),
            description => 'Expense processing with human-in-the-loop'
        );
    END;
    /
    </copy>
    ```

    >**Note:** The `enable_human_tool` attribute activates human-in-the-loop capability—the agent can pause execution and ask for human input when it determines that human judgment is needed.

4. Create the team. This ties together our expense agent and task into a deployable team.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
            team_name   => 'EXPENSE_TEAM',
            attributes  => JSON_OBJECT(
                'agents'  VALUE JSON_ARRAY(
                    JSON_OBJECT('name' VALUE 'EXPENSE_AGENT', 'task' VALUE 'EXPENSE_TASK')
                ),
                'process' VALUE 'sequential'
            ),
            description => 'Expense team with approval workflow'
        );
    END;
    /
    </copy>
    ```

## Task 6: Test the Full Workflow

Now let's run through the complete expense workflow. You'll see how small expenses get auto-approved while larger ones pause for human confirmation—demonstrating the human-in-the-loop pattern in action.

1. Set up the session. This activates the expense team for your database session.

    ```sql
    <copy>
    EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('EXPENSE_TEAM');
    </copy>
    ```

2. Test auto-approved expense (no human needed). Expenses under $100 should be automatically approved based on our rules, with no human intervention required.

    ```sql
    <copy>
    SELECT AI AGENT I need to submit a $45 expense for office supplies;
    </copy>
    ```

    Expected: Auto-approved because $45 < $100 threshold.

3. Test expense requiring approval (human-in-the-loop). This expense exceeds the auto-approval threshold, so the agent will submit it as pending and ask you to confirm the approval.

    ```sql
    <copy>
    SELECT AI AGENT Submit a $250 expense for a team lunch for John Smith;
    </copy>
    ```

    The agent will submit the expense (status = PENDING), detect it needs approval ($250 >= $100), and ask you for confirmation.

4. Respond with approval. Your confirmation triggers the agent to call the approve function, completing the workflow.

    ```sql
    <copy>
    SELECT AI AGENT Yes, I approve it;
    </copy>
    ```

5. Test rejecting an expense. Let's submit another expense that we'll reject, demonstrating the rejection workflow.

    ```sql
    <copy>
    SELECT AI AGENT Submit a $500 expense for client dinner for Jane Doe;
    </copy>
    ```

6. When prompted for approval, reject it explicitly. Being specific about the rejection and providing a reason works more reliably than just saying "no."

    ```sql
    <copy>
    SELECT AI AGENT Reject this expense because entertainment spending is frozen;
    </copy>
    ```

    >**Note:** Being explicit ("Reject this expense because...") works more reliably than just "No, reject it." The clearer your intent, the better the agent understands what action to take.

## Task 7: View All Expenses

Let's examine the expense records to see how both relational columns and JSON details captured the complete workflow history for each expense.

1. Query the expenses table. This view shows the structured fields alongside the flexible JSON details, demonstrating how Oracle's converged approach captures both structured workflow state and rich metadata.

    ```sql
    <copy>
    SELECT 
        RAWTOHEX(expense_id) as id,
        employee_name,
        amount,
        status,
        JSON_SERIALIZE(details PRETTY) as details_json
    FROM expenses
    ORDER BY submitted_at DESC;
    </copy>
    ```

## Task 8: Use Built-in Audit Trail

Oracle provides automatic history tracking for agent operations—no custom audit tables needed. These views let you see exactly what tools the agent called, when, and what the results were.

This is critical for agentic memory in production: you need to prove what decisions the agent made and why. When your auditor asks "what happened with expense #12345?", you have the answer.

1. View agent tool history. This shows every tool invocation by the agent, including timestamps and output previews—invaluable for debugging and auditing agent behavior.

    ```sql
    <copy>
    SELECT 
        tool_name,
        TO_CHAR(start_date, 'MM-DD HH24:MI:SS') as started,
        SUBSTR(output, 1, 80) as output_preview
    FROM USER_AI_AGENT_TOOL_HISTORY
    ORDER BY start_date DESC
    FETCH FIRST 20 ROWS ONLY;
    </copy>
    ```

2. View team history. This higher-level view shows team activations and their states, useful for tracking session-level activity.

    ```sql
    <copy>
    SELECT 
        team_name,
        TO_CHAR(start_date, 'MM-DD HH24:MI:SS') as started,
        state
    FROM USER_AI_AGENT_TEAM_HISTORY
    ORDER BY start_date DESC
    FETCH FIRST 10 ROWS ONLY;
    </copy>
    ```

    This shows you exactly which tools the agent used and when—complete observability without any custom logging code.

## Summary

Congratulations! You've built a production-ready AI agent system with human-in-the-loop approval and complete observability.

To summarize what you accomplished:

* Created an expense workflow combining relational constraints with JSON flexibility
* Enabled human-in-the-loop approval using `enable_human_tool`
* Built complete expense submission, approval, and rejection workflows
* Used built-in history views for observability and audit

---

## Workshop Complete: The Full Picture

Across all three labs, you've built a complete **memory core** that gives AI agents **agentic memory**:

| Lab | What You Built | Why It Matters |
|-----|----------------|----------------|
| **1** | JSON-based fact storage | Flexible memory that adapts to any fact structure |
| **2** | Vector search + ONNX embeddings | Semantic understanding—find facts by meaning |
| **3** | Human-in-the-loop + audit trails | Trust and accountability for production use |

Your agent now:
- ✅ Stores flexible facts as JSON
- ✅ Searches by meaning with vectors
- ✅ Generates embeddings with ONNX (no external APIs)
- ✅ Follows JSON-configured business rules
- ✅ Enforces relational constraints
- ✅ Asks humans when needed
- ✅ Logs everything automatically

**All in one database. All in one transaction. All queryable with SQL.**

### Why This Matters

In 2026, the most valuable AI systems will be the ones built on a memory core—a system that stores context, experience, and enterprise knowledge so agents can learn and perform with continuity.

You just built one.

Without a memory core, AI gives isolated answers. With a memory core, it becomes capable of driving real outcomes. The difference between AI that demos well and AI that actually runs your business.

### What's Next

Now that you understand the pattern, consider:
- **Expanding the memory types**: Add history (what happened), rules (what should happen), and episodic memory (how past situations were resolved)
- **Multi-agent workflows**: Create specialized agents that share a common memory core
- **Integration with your systems**: Connect the memory core to your existing data through views and synonyms
- **Advanced approval workflows**: Multi-level approvals, delegation, escalation timeouts

## Learn More

* [DBMS_CLOUD_AI_AGENT Package](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-cloud-ai-agent-package.html)
* [JSON Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/adjsn/)

## Acknowledgements

* **Author** - David Start
* **Last Updated By/Date** - David Start, December 2025
