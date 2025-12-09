# Give Your Agent a Memory

## Introduction

In this lab, you'll build a **memory core**—the foundation that gives AI agents **agentic memory**.

Here's the thing most people miss: LLMs have "memory," but it's chat memory—style, preferences, past discussions. That's useful, but it's not the kind of memory a business runs on. Agentic memory is different: a durable record of decisions, steps, documents, exceptions, and outcomes. This is the continuity that lets work move forward, improve, and stay consistent over time.

Imagine a workplace where everyone performs well, but no one keeps notes or shares what they learned—every task starts from zero. That's how most AI agents operate right now. In this lab, you'll fix that.

You'll create a memory table using JSON for flexible storage, build tools the agent can use to remember and recall facts, and have actual conversations with an AI that uses your database as its memory core.

This isn't a simulation—you'll actually converse with an AI agent that uses your database as its memory core.

Estimated Time: 15 minutes

### Objectives

* Create an AI profile that connects to your LLM provider
* Build a memory core using Oracle's native JSON type
* Create PL/SQL functions as agent tools for agentic memory
* Register tools with the agent framework
* Have conversations with an agent that has true agentic memory

### Prerequisites

This lab assumes you have:

* An Oracle Cloud account with access to Oracle Database 26ai
* Access to an AI provider (OCI Generative AI, OpenAI, etc.)
* Credentials configured for your AI provider
* Basic knowledge of SQL and PL/SQL

## Task 1: Create an AI Profile

An AI profile defines how Oracle Database connects to your Large Language Model (LLM) provider. This profile stores the credentials, model selection, and provider-specific settings that the agent framework will use for all AI interactions.

1. Create the AI profile using OCI Generative AI. This configuration tells Oracle which cloud provider to use, which credentials to authenticate with, and which specific model to call when the agent needs to generate responses.

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
            ),
            description  => 'Profile for memory-enabled agents'
        );
    END;
    /
    </copy>
    ```

    >**Note:** If you're using OpenAI instead, use this profile configuration:
    >```sql
    >BEGIN
    >    DBMS_CLOUD_AI.CREATE_PROFILE(
    >        profile_name => 'AGENT_PROFILE',
    >        attributes   => JSON_OBJECT(
    >            'provider'        VALUE 'openai',
    >            'credential_name' VALUE 'OPENAI_CRED',
    >            'model'           VALUE 'gpt-4o'
    >        ),
    >        description  => 'Profile for memory-enabled agents'
    >    );
    >END;
    >/
    >```

## Task 2: Create the Memory Core Table

The memory table is the foundation of your agent's memory core—where it stores everything it learns. This is what transforms chat memory into agentic memory.

By using Oracle's native JSON type for the `content` column, we get the flexibility to store any fact structure without predefined schemas—the agent can remember a customer's email preference today and their timezone tomorrow without any ALTER TABLE statements. This flexibility is essential for agentic memory, where the types of facts worth remembering evolve with your business.

1. Create the memory core table with native JSON support. The `memory_id` uses `SYS_GUID()` for globally unique identifiers, while `memory_type` lets us categorize different kinds of agentic memories (facts, preferences, history).

    ```sql
    <copy>
    CREATE TABLE agent_memory (
        memory_id      RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
        agent_id       VARCHAR2(100) DEFAULT 'DEFAULT_AGENT',
        memory_type    VARCHAR2(20) DEFAULT 'FACT',
        content        JSON NOT NULL,
        created_at     TIMESTAMP DEFAULT SYSTIMESTAMP
    );
    </copy>
    ```

2. Create indexes for efficient JSON queries. The functional index on `m.content.about.string()` allows fast lookups when searching for facts about a specific entity, while the index on `memory_type` speeds up filtering by category.

    ```sql
    <copy>
    CREATE INDEX idx_memory_about ON agent_memory m (m.content.about.string());
    CREATE INDEX idx_memory_type ON agent_memory(memory_type);
    </copy>
    ```

    >**Note:** The `content` column is native `JSON` type—not VARCHAR2 storing JSON text. Oracle validates, indexes, and optimizes it automatically. This is what makes it a true memory core rather than just a text dump.

## Task 3: Create the Remember Function

This function becomes the agent's "save to memory core" capability—the write side of agentic memory. When the agent decides something is worth remembering, it calls this function to persist the fact as structured JSON. The `PRAGMA AUTONOMOUS_TRANSACTION` is critical—it allows the function to commit its own transaction even when called from within a query context.

1. Create the function to store facts in memory. The function accepts three parameters: the fact itself, an optional category for organization, and an optional "about" field to link the fact to a specific entity like a customer or product.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION remember_fact(
        p_fact     VARCHAR2,
        p_category VARCHAR2 DEFAULT 'general',
        p_about    VARCHAR2 DEFAULT NULL
    ) RETURN VARCHAR2 AS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO agent_memory (memory_type, content)
        VALUES (
            'FACT',
            JSON_OBJECT(
                'fact'       VALUE p_fact,
                'category'   VALUE p_category,
                'about'      VALUE p_about,
                'source'     VALUE 'conversation',
                'remembered' VALUE TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')
            )
        );
        COMMIT;
        
        RETURN 'Remembered: ' || p_fact || 
               CASE WHEN p_about IS NOT NULL THEN ' (about ' || p_about || ')' ELSE '' END;
    END;
    /
    </copy>
    ```

## Task 4: Create the Recall Function

The recall function is the agent's "search memory core" capability—the read side of agentic memory. It queries the memory table using optional filters for entity name and category, returning the most recent matching facts. This gives the agent the ability to answer questions like "What do you know about Acme Corp?" by searching its stored memories.

Without this capability, AI gives isolated answers. With it, the agent becomes capable of driving real outcomes.

1. Create the function to retrieve facts from memory. The function uses JSON dot notation (`m.content.fact.string()`) to extract fields directly from the JSON column—no parsing or string manipulation needed.

    ```sql
    <copy>
    CREATE OR REPLACE FUNCTION recall_facts(
        p_about    VARCHAR2 DEFAULT NULL,
        p_category VARCHAR2 DEFAULT NULL
    ) RETURN CLOB AS
        v_result CLOB := '';
        v_count  NUMBER := 0;
    BEGIN
        FOR rec IN (
            SELECT 
                m.content.fact.string() as fact,
                m.content.category.string() as category,
                m.content.about.string() as about,
                created_at
            FROM agent_memory m
            WHERE memory_type = 'FACT'
            AND (p_about IS NULL OR UPPER(m.content.about.string()) = UPPER(p_about))
            AND (p_category IS NULL OR UPPER(m.content.category.string()) = UPPER(p_category))
            ORDER BY created_at DESC
            FETCH FIRST 10 ROWS ONLY
        ) LOOP
            v_result := v_result || '- ' || rec.fact;
            IF rec.about IS NOT NULL THEN
                v_result := v_result || ' (about: ' || rec.about || ')';
            END IF;
            v_result := v_result || CHR(10);
            v_count := v_count + 1;
        END LOOP;
        
        IF v_count = 0 THEN
            RETURN 'No facts found matching the criteria.';
        END IF;
        
        RETURN 'Found ' || v_count || ' facts:' || CHR(10) || v_result;
    END;
    /
    </copy>
    ```

    >**Note:** The JSON dot notation `m.content.fact.string()` extracts the `fact` field as a string. No parsing, no SUBSTR—just clean access to nested JSON fields.

## Task 5: Register the Agent Tools

Tools are the bridge between your PL/SQL functions and the AI agent—they connect the memory core to the agent's reasoning. When you register a tool, you're teaching the agent that this capability exists, when to use it, and how to call it. The `instruction` attribute is especially important—it's natural language guidance that helps the LLM understand the tool's purpose.

1. Register the "remember" tool. The instruction tells the agent when this tool is appropriate (storing facts worth remembering) and specifies that parameter names must be uppercase—a requirement of the Oracle agent framework.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'REMEMBER_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Use this tool to store a fact that should be remembered for future conversations. ' ||
                                    'Call this when the user tells you something worth remembering about a person, ' ||
                                    'customer, product, or any entity. ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_FACT (the fact to store), P_CATEGORY (type like preferences, contact, history), P_ABOUT (entity name).',
                'function'    VALUE 'remember_fact'
            ),
            description => 'Stores facts in long-term memory'
        );
    END;
    /
    </copy>
    ```

2. Register the "recall" tool. This tool's instruction emphasizes that it retrieves facts from memory, guiding the agent to use it when answering questions about entities it may have learned about previously.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
            tool_name   => 'RECALL_TOOL',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Use this tool to retrieve facts from memory. ' ||
                                    'Call this when you need to know something about a person, customer, or entity. ' ||
                                    'IMPORTANT: Use UPPERCASE parameter names: ' ||
                                    'P_ABOUT (entity name to look up), P_CATEGORY (optional filter).',
                'function'    VALUE 'recall_facts'
            ),
            description => 'Retrieves facts from long-term memory'
        );
    END;
    /
    </copy>
    ```

3. Verify the tools were created. Both tools should show a status of `ENABLED`, indicating they're ready for the agent to use.

    ```sql
    <copy>
    SELECT tool_name, status, description 
    FROM USER_AI_AGENT_TOOLS;
    </copy>
    ```

## Task 6: Create the Agent, Task, and Team

The agent framework uses three components that work together: an **agent** (with a personality and role), a **task** (specific instructions for handling requests), and a **team** (which orchestrates one or more agents). This separation allows you to reuse agents across different tasks or combine multiple agents for complex workflows.

This is where your memory core becomes agentic memory—the agent gains the ability to decide when to remember and when to recall.

1. Create the agent. The `role` attribute defines the agent's personality and core behaviors. Here we're telling it to proactively use the memory core rather than claiming ignorance—this is what makes it capable of building on what worked and avoiding repeated mistakes.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
            agent_name  => 'MEMORY_AGENT',
            attributes  => JSON_OBJECT(
                'profile_name' VALUE 'AGENT_PROFILE',
                'role'         VALUE 'You are a helpful assistant with the ability to remember facts. ' ||
                                     'When users tell you things worth remembering, use the REMEMBER_TOOL to store them. ' ||
                                     'When users ask about something, use the RECALL_TOOL to check what you know. ' ||
                                     'Always check your memory before saying you don''t know something.'
            ),
            description => 'An agent that remembers things'
        );
    END;
    /
    </copy>
    ```

2. Create a task. The task provides specific instructions for handling each user request. The `{query}` placeholder gets replaced with the actual user input. We explicitly limit tool calls to prevent the agent from over-iterating.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TASK(
            task_name   => 'MEMORY_TASK',
            attributes  => JSON_OBJECT(
                'instruction' VALUE 'Process this single user request. ' ||
                                    'If the user shares information worth remembering, call REMEMBER_TOOL once, then give a brief confirmation. ' ||
                                    'If the user asks a question, call RECALL_TOOL once, then answer based on what you found. ' ||
                                    'Use at most ONE tool call, then provide your final response. Do not call additional tools. ' ||
                                    'User request: {query}',
                'tools'       VALUE JSON_ARRAY('REMEMBER_TOOL', 'RECALL_TOOL')
            ),
            description => 'Task for memory-enabled conversations'
        );
    END;
    /
    </copy>
    ```

3. Create the team. The team ties everything together, specifying which agent handles which task. The `sequential` process means requests are handled one at a time in order.

    ```sql
    <copy>
    BEGIN
        DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
            team_name   => 'MEMORY_TEAM',
            attributes  => JSON_OBJECT(
                'agents'  VALUE JSON_ARRAY(
                    JSON_OBJECT('name' VALUE 'MEMORY_AGENT', 'task' VALUE 'MEMORY_TASK')
                ),
                'process' VALUE 'sequential'
            ),
            description => 'Team with memory-enabled agent'
        );
    END;
    /
    </copy>
    ```

4. Verify everything is set up. All three components should show `ENABLED` status, indicating the agent system is ready to use.

    ```sql
    <copy>
    SELECT team_name, status FROM USER_AI_AGENT_TEAMS;
    SELECT agent_name, status FROM USER_AI_AGENT_AGENTS;
    SELECT task_name, status FROM USER_AI_AGENT_TASKS;
    </copy>
    ```

## Task 7: Talk to Your Agent

Now the fun part—actually using an agent with agentic memory! The `SELECT AI AGENT` syntax is Oracle's natural language interface to your agent team. Whatever you type after these keywords becomes the user request that flows through your task instruction.

When agents have a real memory core, they can build on what worked, avoid repeated mistakes, adapt to your workflows, carry context across tasks, and deliver consistent results. Let's see it in action.

1. Set the team for your session. This tells Oracle which agent team should handle your AI AGENT queries for this database session.

    ```sql
    <copy>
    EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('MEMORY_TEAM');
    </copy>
    ```

2. Tell the agent something to remember. The agent should recognize this as information worth storing and call the REMEMBER_TOOL automatically.

    ```sql
    <copy>
    SELECT AI AGENT Customer Acme Corp prefers to be contacted by email, not phone;
    </copy>
    ```

    The agent should respond with something like: "I've stored that fact. Acme Corp prefers email contact over phone. Is there anything else you'd like me to remember about them?"

3. Tell it more. Each fact gets stored as a separate JSON document in the memory table, building up the agent's knowledge about this entity.

    ```sql
    <copy>
    SELECT AI AGENT Acme Corp's main contact is Sarah Johnson and their timezone is Pacific;
    </copy>
    ```

4. Now ask about what it knows. The agent should call RECALL_TOOL to search its memory before answering, returning all the facts it has stored about Acme Corp.

    ```sql
    <copy>
    SELECT AI AGENT What do you know about Acme Corp;
    </copy>
    ```

    The agent should respond with the stored facts: "Based on my memory, here's what I know about Acme Corp: They prefer to be contacted by email, not phone. Their main contact is Sarah Johnson. They are in the Pacific timezone."

## Task 8: Verify the Memory Core Contents

Let's look behind the scenes to see how agentic memory is actually stored. This demonstrates the power of Oracle's native JSON type as a memory core—structured data that's queryable with SQL but flexible enough to store any fact structure.

This is the difference between chat memory (which forgets) and agentic memory (which persists and compounds).

1. View the actual JSON stored in the database. The `JSON_SERIALIZE` function with `PRETTY` formatting shows the complete JSON structure of each memory, including metadata like when it was remembered.

    ```sql
    <copy>
    SELECT 
        memory_type,
        JSON_SERIALIZE(content PRETTY) as content_json,
        created_at
    FROM agent_memory
    ORDER BY created_at DESC;
    </copy>
    ```

    You'll see JSON like:
    ```json
    {
      "fact": "Customer Acme Corp prefers to be contacted by email, not phone",
      "category": "preferences",
      "about": "Acme Corp",
      "source": "conversation",
      "remembered": "2024-12-02 14:23:01"
    }
    ```

2. Test with a new entity. This demonstrates that the agent can track multiple entities independently, each with their own set of facts.

    ```sql
    <copy>
    SELECT AI AGENT Remember that customer TechStart Inc is a new customer, 
    signed up last week, and their account manager is Bob Wilson;
    </copy>
    ```

3. Ask about all customers. The agent should search its memory and find facts about both Acme Corp and TechStart Inc.

    ```sql
    <copy>
    SELECT AI AGENT What customers do you know about;
    </copy>
    ```

    The agent should mention both Acme Corp and TechStart Inc.

## Task 9: Verify Agentic Memory Persists Across Sessions

The key differentiator of a database-backed memory core is persistence. Unlike in-memory caches or session-based storage, facts stored in Oracle Database survive restarts, reconnections, and even application updates.

This is what makes it agentic memory: the work compounds over time. Every task doesn't start from zero.

1. Clear and reset the session. This simulates closing your application and starting a new session—the agent framework state is cleared.

    ```sql
    <copy>
    EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
    </copy>
    ```

2. Set the team again (simulating a new session). You're reconnecting to the same agent team, but with a fresh session context.

    ```sql
    <copy>
    EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('MEMORY_TEAM');
    </copy>
    ```

3. Ask about previous information. Because the facts are stored in the memory core (not session memory), the agent can still recall everything it learned.

    ```sql
    <copy>
    SELECT AI AGENT Who is the contact for Acme Corp;
    </copy>
    ```

    The agent remembers because the facts are in the memory core—this is agentic memory in action.

## Summary

Congratulations! You built a **memory core** that gives your AI agent **agentic memory** using Oracle's native JSON type.

To summarize what you accomplished:

* Created an AI profile connecting to your LLM provider
* Built a memory core using Oracle's native JSON type
* Created PL/SQL functions as agent tools (remember and recall)
* Registered tools with the agent framework
* Created an agent, task, and team with access to the memory core
* Had actual conversations with an agent that has agentic memory
* Verified that agentic memory persists across sessions

**This is a real agent, not a simulation.** The agent decides when to use its memory core—you just have a conversation.

In 2026, the most valuable AI systems will be the ones built on a memory core—a system that stores context, experience, and enterprise knowledge so agents can learn and perform with continuity. You just built one.

### Why This Matters for Your Industry

As agentic memory hits major industries, it becomes the differentiator between AI experiments and real transformation:

| Industry | Why Agentic Memory Matters |
|----------|---------------------------|
| **Healthcare** | Remember patient history, treatment decisions, care plan exceptions across visits |
| **Finance** | Track advisory conversations, compliance decisions, risk assessments over time |
| **Retail** | Build customer preferences, purchase patterns, service history that persists |
| **Logistics** | Learn from routing decisions, exception handling, carrier performance |
| **HR** | Maintain candidate interactions, policy exceptions, onboarding progress |

You may now proceed to the next lab.

## Learn More

* [DBMS_CLOUD_AI_AGENT Package](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-cloud-ai-agent-package.html)
* [JSON Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/adjsn/)

## Acknowledgements

* **Author** - David Start
* **Last Updated By/Date** - David Start, December 2025
