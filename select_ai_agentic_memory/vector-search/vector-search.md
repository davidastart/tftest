# Memory That Understands

## Introduction

In Lab 1, you gave your agent a memory core—the ability to store and recall facts. But that memory uses exact matching: the agent can only find facts if you use the same keywords you stored them with.

Real agentic memory needs to be smarter. When you ask "how should I reach out to Acme?" the agent should find the fact "Acme prefers email contact" even though those phrases share no keywords. This is **semantic search**—finding information by meaning, not just words.

In this lab, you'll upgrade your memory core with Oracle's VECTOR data type and in-database ONNX models. Your agent will find facts by meaning, not just keywords—so "contact info" finds "prefers email" even though those words don't match exactly.

You'll also add a rules engine using JSON, giving your agent business logic to follow. This combination—semantic memory plus configurable rules—is what transforms an agent from a chatbot into a system that can actually run workflows.

Estimated Time: 20 minutes

### Objectives

* Load an ONNX embedding model into the database
* Add VECTOR columns to store semantic embeddings
* Create semantic search functions using VECTOR_DISTANCE
* Build a JSON-based business rules engine
* Register enhanced tools with the agent framework

### Prerequisites

This lab assumes you have:

* Completed Lab 1: Give Your Agent a Memory
* Oracle Database 26ai with Select AI Agent
* Basic knowledge of SQL and PL/SQL

## Task 1: Load the ONNX Embedding Model

Embedding models convert text into numerical vectors that capture semantic meaning. Two sentences with similar meaning will have similar vectors, even if they use completely different words.

By loading an ONNX model directly into Oracle Database, you can generate these embeddings with SQL—no external API calls, no network latency, and no per-request costs. The embedding model becomes part of your memory core.

1. Download the model from Oracle's public object storage. This retrieves the all-MiniLM-L12-v2 model file (a popular open-source embedding model from Hugging Face) and stores it in your database's DATA_PUMP_DIR directory.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD.GET_OBJECT(
            credential_name => NULL,
            directory_name  => 'DATA_PUMP_DIR',
            object_uri      => 'https://adwc4pm.objectstorage.us-ashburn-1.oci.customer-oci.com/' ||
                               'p/eLddQappgBJ7jNi6Guz9m9LOtYe2u8LWY19GfgU8flFK4N9YgP4kTlrE9Px3pE12/' ||
                               'n/adwc4pm/b/OML-Resources/o/all_MiniLM_L12_v2.onnx'
        );
    END;
    /
    </copy>
    ```

2. Load the model into the database. This imports the ONNX model as a database object that can be referenced by name in SQL statements. Once loaded, the model runs entirely within the database engine.

    ```sql
    <copy>
    BEGIN
        DBMS_VECTOR.LOAD_ONNX_MODEL(
            directory  => 'DATA_PUMP_DIR',
            file_name  => 'all_MiniLM_L12_v2.onnx',
            model_name => 'ALL_MINILM_L12_V2'
        );
    END;
    /
    </copy>
    ```

3. Verify the model is loaded. You should see the model registered with `ONNX` as the algorithm and `EMBEDDING` as the mining function, confirming it's ready to generate vector embeddings.

    ```sql
    <copy>
    SELECT model_name, algorithm, mining_function 
    FROM user_mining_models 
    WHERE model_name = 'ALL_MINILM_L12_V2';
    </copy>
    ```

    Expected output:
    ```
    MODEL_NAME          ALGORITHM  MINING_FUNCTION
    ------------------  ---------  ---------------
    ALL_MINILM_L12_V2   ONNX       EMBEDDING
    ```

    >**Note:** The **all-MiniLM-L12-v2** model from Hugging Face produces 384-dimensional vectors, is optimized for semantic similarity, and is free and open source. It runs entirely in-database with no external API calls.

## Task 2: Add VECTOR Column to the Memory Core

Oracle's VECTOR data type stores high-dimensional numerical arrays efficiently. By adding a VECTOR column to our memory table, each fact can have an associated embedding that captures its semantic meaning, enabling similarity searches.

This is what upgrades your memory from keyword-based to meaning-based—the key to true agentic memory.

1. Add the VECTOR type column. The `VECTOR(384)` specification indicates this column will store 384-dimensional vectors—matching the output dimensions of our loaded ONNX model.

    ```sql
    <copy>
    ALTER TABLE agent_memory ADD (
        embedding VECTOR(384)
    );
    </copy>
    ```

2. Create a vector index for fast similarity search. This specialized index structure (using NEIGHBOR PARTITIONS) enables efficient approximate nearest neighbor searches, making similarity queries fast even with millions of vectors.

    ```sql
    <copy>
    CREATE VECTOR INDEX idx_memory_vector ON agent_memory(embedding)
    ORGANIZATION NEIGHBOR PARTITIONS
    DISTANCE COSINE
    WITH TARGET ACCURACY 95;
    </copy>
    ```

    >**Note:** `VECTOR(384)` is a native type, just like `NUMBER` or `VARCHAR2`. Oracle validates dimensions and optimizes storage automatically.

## Task 3: Create Enhanced Remember Function

Now when we store a fact in the memory core, we also generate its embedding in the same transaction. The `VECTOR_EMBEDDING` function calls our loaded ONNX model to convert the fact text into a 384-dimensional vector that captures its semantic meaning.

This is the magic of Oracle's converged database: JSON content and vector embeddings stored together, indexed together, queried together.

1. Drop the old function and create the enhanced version. The key addition is the `VECTOR_EMBEDDING` call that generates an embedding from the fact text and stores it alongside the JSON content.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION remember_fact(
        p_fact     VARCHAR2,
        p_category VARCHAR2 DEFAULT 'general',
        p_about    VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 AS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO agent_memory (memory_type, content, embedding)
        VALUES (
            'FACT',
            JSON_OBJECT(
                'fact'       VALUE p_fact,
                'category'   VALUE p_category,
                'about'      VALUE p_about,
                'source'     VALUE 'conversation',
                'remembered' VALUE TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')
            ),
            VECTOR_EMBEDDING(ALL_MINILM_L12_V2 USING p_fact AS DATA)
        );
        COMMIT;
        
        RETURN 'Remembered: ' || p_fact || 
               CASE WHEN p_about IS NOT NULL THEN ' (about ' || p_about || ')' ELSE '' END;
    END;
    /
    </copy>
    ```

    >**Note:** The key line `VECTOR_EMBEDDING(ALL_MINILM_L12_V2 USING p_fact AS DATA)` generates a 384-dimension vector from the fact text—entirely in SQL, no external API.

## Task 4: Create Semantic Search Function

This is where the magic of agentic memory happens. Instead of matching keywords, we compare the semantic meaning of the search query against stored facts. The `VECTOR_DISTANCE` function calculates how similar two vectors are, allowing us to find facts that are conceptually related even when they use different words.

This is what lets an agent "understand" what you're asking for, not just pattern-match against stored text.

1. Create the semantic search function. This function embeds the query text on-the-fly, then orders all stored facts by their semantic similarity to that query, returning the most relevant matches.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION search_memory(
        p_query    VARCHAR2,
        p_about    VARCHAR2 DEFAULT NULL,
        p_limit    NUMBER DEFAULT 5
    ) RETURN CLOB AS
        v_result CLOB := '';
        v_count  NUMBER := 0;
    BEGIN
        FOR rec IN (
            SELECT 
                m.content.fact.string() as fact,
                m.content.about.string() as about,
                m.content.category.string() as category,
                ROUND(1 - VECTOR_DISTANCE(
                    embedding, 
                    VECTOR_EMBEDDING(ALL_MINILM_L12_V2 USING p_query AS DATA), 
                    COSINE
                ), 3) AS similarity
            FROM agent_memory m
            WHERE embedding IS NOT NULL
            AND (p_about IS NULL OR UPPER(m.content.about.string()) LIKE '%' || UPPER(p_about) || '%')
            ORDER BY VECTOR_DISTANCE(
                embedding, 
                VECTOR_EMBEDDING(ALL_MINILM_L12_V2 USING p_query AS DATA), 
                COSINE
            )
            FETCH FIRST p_limit ROWS ONLY
        ) LOOP
            v_result := v_result || '- ' || rec.fact;
            IF rec.about IS NOT NULL THEN
                v_result := v_result || ' [' || rec.about || ']';
            END IF;
            v_result := v_result || ' (relevance: ' || rec.similarity || ')' || CHR(10);
            v_count := v_count + 1;
        END LOOP;
        
        IF v_count = 0 THEN
            RETURN 'No relevant facts found for: ' || p_query;
        END IF;
        
        RETURN 'Found ' || v_count || ' relevant facts:' || CHR(10) || v_result;
    END;
    /
    </copy>
    ```

    >**Note:** The function embeds the query text with `VECTOR_EMBEDDING(...USING p_query AS DATA)`, compares to stored embeddings with `VECTOR_DISTANCE(..., COSINE)`, and returns the closest matches by semantic similarity.

## Task 5: Create Business Rules Table

Business rules define how your agent should behave in specific situations. By storing rules as JSON, you can add new rule types, modify thresholds, or change actions without any schema changes—just update the JSON configuration.

1. Create the rules table. Each rule has a name, a JSON configuration (containing conditions and actions), a priority (higher numbers = checked first), and an active flag for easy enable/disable.

    ```sql
    <copy>
    CREATE TABLE agent_rules (
        rule_id        RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
        rule_name      VARCHAR2(200) NOT NULL,
        rule_config    JSON NOT NULL,
        priority       NUMBER DEFAULT 100,
        is_active      NUMBER(1) DEFAULT 1,
        created_at     TIMESTAMP DEFAULT SYSTIMESTAMP
    );
    </copy>
    ```

2. Add expense rules as JSON. These rules define approval thresholds: expenses under $100 auto-approve, $100-$500 need manager approval, $500+ need director approval, and entertainment expenses always get flagged.

    ```sql
    <copy>
    INSERT INTO agent_rules (rule_name, rule_config, priority) VALUES (
        'Auto-approve small expenses',
        JSON_OBJECT(
            'condition' VALUE JSON_OBJECT(
                'field' VALUE 'amount',
                'operator' VALUE 'lt',
                'value' VALUE 100
            ),
            'action' VALUE 'AUTO_APPROVE',
            'message' VALUE 'Amount under $100 auto-approval threshold'
        ),
        100
    );

    INSERT INTO agent_rules (rule_name, rule_config, priority) VALUES (
        'Manager approval for medium',
        JSON_OBJECT(
            'condition' VALUE JSON_OBJECT(
                'field' VALUE 'amount',
                'operator' VALUE 'between',
                'min' VALUE 100,
                'max' VALUE 500
            ),
            'action' VALUE 'REQUIRE_MANAGER_APPROVAL',
            'message' VALUE 'Amounts $100-$500 require manager approval'
        ),
        90
    );

    INSERT INTO agent_rules (rule_name, rule_config, priority) VALUES (
        'Director approval for large',
        JSON_OBJECT(
            'condition' VALUE JSON_OBJECT(
                'field' VALUE 'amount',
                'operator' VALUE 'gte',
                'value' VALUE 500
            ),
            'action' VALUE 'REQUIRE_DIRECTOR_APPROVAL',
            'message' VALUE 'Amounts $500+ require director approval'
        ),
        80
    );

    INSERT INTO agent_rules (rule_name, rule_config, priority) VALUES (
        'Flag entertainment',
        JSON_OBJECT(
            'condition' VALUE JSON_OBJECT(
                'field' VALUE 'category',
                'operator' VALUE 'eq',
                'value' VALUE 'entertainment'
            ),
            'action' VALUE 'FLAG_FOR_REVIEW',
            'message' VALUE 'Entertainment expenses require additional review'
        ),
        110
    );

    COMMIT;
    </copy>
    ```

## Task 6: Create Rule Evaluation Function

This function evaluates business rules by extracting conditions from JSON and comparing them against input values. It iterates through active rules in priority order and returns the first matching rule's action and message.

1. Create the function to check business rules. The function uses `JSON_VALUE` to extract fields from the rule configuration, then evaluates different operator types (less than, greater than or equal, between, equals) against the input parameters.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION check_rules(
        p_amount   NUMBER DEFAULT NULL,
        p_category VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 AS
    BEGIN
        FOR rec IN (
            SELECT 
                rule_name,
                JSON_VALUE(rule_config, '$.action') as action,
                JSON_VALUE(rule_config, '$.message') as message,
                JSON_VALUE(rule_config, '$.condition.field') as cond_field,
                JSON_VALUE(rule_config, '$.condition.operator') as cond_operator,
                JSON_VALUE(rule_config, '$.condition.value' RETURNING NUMBER) as cond_value,
                JSON_VALUE(rule_config, '$.condition.value') as cond_value_str,
                JSON_VALUE(rule_config, '$.condition.min' RETURNING NUMBER) as cond_min,
                JSON_VALUE(rule_config, '$.condition.max' RETURNING NUMBER) as cond_max
            FROM agent_rules
            WHERE is_active = 1
            ORDER BY priority DESC
        ) LOOP
            IF p_amount IS NOT NULL AND rec.cond_field = 'amount' THEN
                IF rec.cond_operator = 'lt' AND p_amount < rec.cond_value THEN
                    RETURN 'Rule: ' || rec.rule_name || '. Action: ' || rec.action || '. ' || rec.message;
                ELSIF rec.cond_operator = 'gte' AND p_amount >= rec.cond_value THEN
                    RETURN 'Rule: ' || rec.rule_name || '. Action: ' || rec.action || '. ' || rec.message;
                ELSIF rec.cond_operator = 'between' 
                   AND p_amount >= rec.cond_min AND p_amount < rec.cond_max THEN
                    RETURN 'Rule: ' || rec.rule_name || '. Action: ' || rec.action || '. ' || rec.message;
                END IF;
            END IF;
            
            IF p_category IS NOT NULL AND rec.cond_field = 'category' THEN
                IF rec.cond_operator = 'eq' AND UPPER(p_category) = UPPER(rec.cond_value_str) THEN
                    RETURN 'Rule: ' || rec.rule_name || '. Action: ' || rec.action || '. ' || rec.message;
                END IF;
            END IF;
        END LOOP;
        
        RETURN 'No specific rules apply. Default processing allowed.';
    END;
    /
    </copy>
    ```

## Task 7: Register Enhanced Tools

Now we update our tool registrations to use the new semantic search capability and add the rules checking tool. The instructions guide the agent on when and how to use each tool effectively.

1. Drop old tools and create enhanced versions. We remove the previous keyword-based recall tool to replace it with semantic search.

    ```sql
    <copy>
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TOOL('REMEMBER_TOOL', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TOOL('RECALL_TOOL', TRUE); END;
    /
    </copy>
    ```

2. Create enhanced remember tool. The instruction now mentions "semantic indexing" so the agent understands that stored facts can be found by meaning.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'REMEMBER_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Store a fact in long-term memory with semantic indexing. ' ||
                                    'Use this when the user shares information worth remembering. ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_FACT (what to remember), P_CATEGORY (type: preferences, contact, history, account), ' ||
                                    'P_ABOUT (entity name like customer or person name).',
                'function'    VALUE 'remember_fact'
            ),
            description => 'Stores facts with semantic embedding for intelligent retrieval'
        );
    END;
    /
    </copy>
    ```

3. Create semantic search tool. The instruction explicitly tells the agent that this tool finds facts by meaning, not just keywords, and gives an example of how it works.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'SEARCH_MEMORY_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Search memory for facts relevant to a query using semantic similarity. ' ||
                                    'This finds facts by MEANING, not just keywords. For example, searching for ' ||
                                    '"how to contact" will find facts about "prefers email" or "phone number". ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_QUERY (what to search for), P_ABOUT (optional: entity to filter by), ' ||
                                    'P_LIMIT (optional: max results, default 5).',
                'function'    VALUE 'search_memory'
            ),
            description => 'Semantic search across memory'
        );
    END;
    /
    </copy>
    ```

4. Create rules tool. This tool lets the agent check business rules before processing requests, ensuring compliance with approval thresholds and policies.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'CHECK_RULES_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Check business rules to determine what action is required. ' ||
                                    'Use this before processing expenses or requests to see if approval is needed. ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_AMOUNT (numeric amount), P_CATEGORY (expense category like meals, travel, supplies, entertainment).',
                'function'    VALUE 'check_rules'
            ),
            description => 'Evaluates business rules to determine required actions'
        );
    END;
    /
    </copy>
    ```

## Task 8: Create the Smart Agent

We need to create a new agent that understands its enhanced capabilities—semantic memory search and rule awareness. The agent's role description shapes how it approaches user requests.

1. Drop old agent components. We remove the previous agent, task, and team to create fresh versions with the new capabilities.

    ```sql
    <copy>
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TEAM('MEMORY_TEAM', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_TASK('MEMORY_TASK', TRUE); END;
    /
    BEGIN DBMS_CLOUD_AI_AGENT.DROP_AGENT('MEMORY_AGENT', TRUE); END;
    /
    </copy>
    ```

2. Create smart agent. The role now emphasizes that the agent can find facts by meaning and should check rules when processing requests involving amounts or categories.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
            agent_name  => 'SMART_AGENT',
            attributes  => JSON_OBJECT(
                'profile_name' VALUE 'AGENT_PROFILE',
                'role'         VALUE 'You are an intelligent assistant with semantic memory and business rules awareness. ' ||
                                     'You can remember facts about customers and entities, and find them by meaning. ' ||
                                     'When processing requests involving amounts or categories, always check the rules first. ' ||
                                     'Be proactive about using your memory - search for relevant context before responding.'
            ),
            description => 'Agent with semantic memory and rule awareness'
        );
    END;
    /
    </copy>
    ```

3. Create smart task. The task instruction maps different user intents to specific tools, with explicit limits on tool calls to prevent over-iteration.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TASK(
            task_name   => 'SMART_TASK',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Process this single user request. ' ||
                                    'If user shares info, call REMEMBER_TOOL once, then confirm. ' ||
                                    'If user asks a question, call SEARCH_MEMORY_TOOL once, then answer. ' ||
                                    'If processing amounts, call CHECK_RULES_TOOL once, then explain. ' ||
                                    'Use at most ONE or TWO tool calls, then provide your final response. Do not continue calling tools. ' ||
                                    'User request: {query}',
                'tools'       VALUE JSON_ARRAY('REMEMBER_TOOL', 'SEARCH_MEMORY_TOOL', 'CHECK_RULES_TOOL')
            ),
            description => 'Task combining memory and rules'
        );
    END;
    /
    </copy>
    ```

4. Create team. The team configuration remains similar, just referencing our new smart agent and task.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
            team_name   => 'SMART_TEAM',
            attributes  => JSON_OBJECT(
                'agents'  VALUE JSON_ARRAY(
                    JSON_OBJECT('name' VALUE 'SMART_AGENT', 'task' VALUE 'SMART_TASK')
                ),
                'process' VALUE 'sequential'
            ),
            description => 'Team with semantic memory and rules'
        );
    END;
    /
    </copy>
    ```

## Task 9: Test the Smart Agent

Let's put the semantic search to the test. We'll store facts using specific words, then search using completely different words that have similar meaning—demonstrating that the agent finds facts by concept, not keyword matching.

1. Set up the session. This activates the new smart team for your database session.

    ```sql
    <copy>
    EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('SMART_TEAM');
    </copy>
    ```

2. Store some facts. We'll use specific language here that we won't use later when searching.

    ```sql
    <copy>
    SELECT AI AGENT Remember that Acme Corp prefers to be contacted via email and their timezone is Pacific;
    </copy>
    ```

    ```sql
    <copy>
    SELECT AI AGENT Remember that Acme Corp has a premium support plan and their renewal date is March 2025;
    </copy>
    ```

    ```sql
    <copy>
    SELECT AI AGENT Remember that our contact at Acme is Sarah Johnson, she is the VP of Operations;
    </copy>
    ```

3. Test semantic search—asking in different ways. Watch how "reach out" finds "prefers email" even though those phrases share no keywords.

    ```sql
    <copy>
    SELECT AI AGENT How should I reach out to Acme;
    </copy>
    ```

    This should find the email preference fact even though "reach out" and "prefers email" don't share keywords!

    ```sql
    <copy>
    SELECT AI AGENT What kind of support does Acme have;
    </copy>
    ```

    ```sql
    <copy>
    SELECT AI AGENT Who do I talk to at Acme;
    </copy>
    ```

4. Test rules. These queries should trigger the rules checking tool to determine what approval level is needed.

    ```sql
    <copy>
    SELECT AI AGENT I need to submit a $50 expense for office supplies;
    </copy>
    ```

    Expected: Auto-approve (under $100 threshold)

    ```sql
    <copy>
    SELECT AI AGENT I need to submit a $250 expense for a team lunch;
    </copy>
    ```

    Expected: Requires manager approval

    ```sql
    <copy>
    SELECT AI AGENT I need to submit a $750 expense for client entertainment;
    </copy>
    ```

    Expected: Requires director approval AND flagged (entertainment category)

## Task 10: Verify the Memory Core Data

Let's examine the underlying data to see how JSON content and vector embeddings are stored together in your memory core—demonstrating Oracle's converged database capabilities in action.

1. See JSON content with embeddings. This query shows both the human-readable JSON and confirms that each fact has a 384-dimensional vector embedding attached.

    ```sql
    <copy>
    SELECT 
        JSON_SERIALIZE(content PRETTY) as fact_json,
        VECTOR_DIMS(embedding) as vector_dimensions
    FROM agent_memory
    WHERE embedding IS NOT NULL
    ORDER BY created_at DESC;
    </copy>
    ```

2. See the rules as JSON. Viewing the rules in formatted JSON shows the flexible structure we used to define conditions and actions.

    ```sql
    <copy>
    SELECT 
        rule_name,
        JSON_SERIALIZE(rule_config PRETTY) as rule_json
    FROM agent_rules
    ORDER BY priority DESC;
    </copy>
    ```

## Summary

Congratulations! You upgraded your memory core with semantic search and business rules using Oracle's converged data types.

To summarize what you accomplished:

* Loaded an ONNX embedding model directly into the database
* Added VECTOR columns to store semantic embeddings in your memory core
* Created functions that generate embeddings with `VECTOR_EMBEDDING`
* Built semantic search using `VECTOR_DISTANCE`
* Created a JSON-based rules engine
* Registered enhanced tools with the agent framework
* Tested semantic search—finding facts by meaning, not keywords

**Why This Matters for Agentic Memory:** You're now using three native Oracle data types together—JSON for flexible fact content, VECTOR for semantic similarity, and relational columns for structure and constraints. One query can use all of them without joins across systems.

This is what makes your agent's memory truly "agentic"—it doesn't just store facts, it understands them well enough to find relevant information even when the question is phrased differently than the answer.

**Oracle Converged Database in Action:** Traditional architectures would require PostgreSQL for relational data, Pinecone for vectors, MongoDB for documents, plus custom code to sync them all. You just did it all in one database, one transaction, one security model.

You may now proceed to the next lab.

## Learn More

* [AI Vector Search Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/)
* [Pre-built ONNX Model for Embeddings](https://blogs.oracle.com/machinelearning/post/use-our-prebuilt-onnx-model-now-available-for-embedding-generation-in-oracle-database-23ai)

## Acknowledgements

* **Author** - David Start
* **Last Updated By/Date** - David Start, December 2025
