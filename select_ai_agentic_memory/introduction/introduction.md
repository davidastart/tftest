# Agentic Memory: When AI Stops Forgetting

## About this Workshop

**If AI can't remember what it did yesterday, it can't run your business tomorrow.**

This is the shift happening right now: AI agents are moving from answering questions to actually doing work. But there's a problem most people miss when they think about AI's limitations.

### The Problem: AI Agents Have Amnesia

Most AI today can remember a conversation, but it can't remember *the work*. 

LLMs have "memory," but it's chat memory—style, preferences, past discussions. That's useful, but it's not the kind of memory a business runs on. When your customer calls back tomorrow, the agent has no idea what happened yesterday. When your expense workflow runs again, it can't learn from last week's exceptions. Every task starts from zero.

Imagine a workplace where everyone performs well, but no one keeps notes or shares what they learned. That's how most AI agents operate right now.

### The Solution: Agentic Memory

What agents actually need is **agentic memory**—a durable record of decisions, steps, documents, exceptions, and outcomes. This is the continuity that lets work move forward, improve, and stay consistent over time.

When agents have a real memory core, they can:
- **Build on what worked** — Learn from successful outcomes
- **Avoid repeated mistakes** — Remember what failed and why
- **Adapt to your workflows** — Store business rules and exceptions
- **Carry context across tasks** — Know what happened yesterday
- **Deliver consistent results** — Apply institutional knowledge

The technology that unlocks all of this isn't another model layer—it's a **converged database** capable of serving as the **memory core** for agentic systems.

### Why This Matters Now

In 2026, the most valuable AI systems will be the ones built on a memory core—a system that stores context, experience, and enterprise knowledge so agents can learn and perform with continuity.

As agentic memory hits major industries that run on workflows, it becomes the differentiator between AI experiments and real transformation:

| Industry | Why Agentic Memory Matters |
|----------|---------------------------|
| **Healthcare** | Remember patient history, treatment decisions, care plan exceptions across visits |
| **Finance** | Track advisory conversations, compliance decisions, risk assessments over time |
| **Retail** | Build customer preferences, purchase patterns, service history that persists |
| **Logistics** | Learn from routing decisions, exception handling, carrier performance |
| **HR** | Maintain candidate interactions, policy exceptions, onboarding progress |

Without a memory core, AI gives isolated answers. With a memory core, it becomes capable of driving real outcomes.

---

## What You'll Build

This hands-on workshop takes you from zero to a production-ready AI agent with agentic memory in three progressive labs:

### Lab 1: Give Your Agent a Memory
*Create the foundation of agentic memory*

You'll create a memory table using JSON for flexible storage, build tools the agent can use to remember and recall facts, and have actual conversations with an AI that remembers.

**What you'll learn:**
- How Oracle's native JSON type enables schema-free fact storage
- How to create PL/SQL functions as agent tools
- How to register tools with the Select AI Agent framework
- How agentic memory persists across sessions

### Lab 2: Memory That Understands
*Add semantic understanding to your memory core*

You'll add the VECTOR data type for semantic embeddings, load an ONNX model to generate embeddings in-database, and enable your agent to find facts by meaning—so "contact info" finds "prefers email" even though those words don't match exactly.

**What you'll learn:**
- How to load ONNX embedding models directly into the database
- How VECTOR columns enable semantic similarity search
- How to combine JSON, VECTOR, and relational data in one query
- How to build a JSON-based business rules engine

### Lab 3: Agents You Can Trust
*Add human oversight and accountability*

You'll implement human-in-the-loop approval workflows, build a complete expense processing system, and use built-in audit trails to see everything your agent does.

**What you'll learn:**
- How to enable human-in-the-loop with `enable_human_tool`
- How to combine relational constraints with JSON flexibility
- How to use built-in history views for observability and audit
- How to build workflows that require human judgment for critical decisions

---

## Why Oracle's Converged Database as a Memory Core

Traditional approaches to giving agents memory require multiple specialized systems—a relational database for structured data, a vector database for embeddings, a document store for flexible content, a caching layer for speed—plus custom code to sync them all and keep them consistent.

**That's fragile.** Data gets out of sync. Transactions span systems. Security has gaps. And your agent's "memory" is scattered across infrastructure you have to maintain.

Oracle Database 26ai gives you everything in one place—a true **memory core** for your agents:

| Data Type | What It's For | Agent Use Case |
|-----------|---------------|----------------|
| **JSON** | Flexible, schema-less data | Store any fact structure without ALTER TABLE |
| **VECTOR** | Semantic embeddings | Find facts by meaning, not keywords |
| **Relational** | Structured data with constraints | Rules, approvals, audit trails, workflow state |
| **ONNX Models** | In-database ML models | Generate embeddings without external APIs |

**One query can use all of them:**

```sql
SELECT m.content.fact.string()
FROM agent_memory m
WHERE m.content.category.string() = 'preferences'
ORDER BY VECTOR_DISTANCE(embedding, query_vec, COSINE)
FETCH FIRST 5 ROWS ONLY;
```

JSON filtering. Vector similarity. Relational ordering. One SQL statement. One transaction. One security model.

By the end of this workshop, you'll have built an agent that:
- ✅ Stores flexible facts as JSON
- ✅ Searches by meaning with vectors
- ✅ Generates embeddings with ONNX (no external APIs)
- ✅ Follows JSON-configured business rules
- ✅ Enforces relational constraints
- ✅ Asks humans when needed
- ✅ Logs everything automatically

**All in one database. All in one transaction. All queryable with SQL.**

---

## Prerequisites

This workshop assumes you have:

* An Oracle Cloud account with access to Oracle Database 26ai
* Access to an AI provider (OCI Generative AI, OpenAI, etc.)
* Credentials configured for your AI provider
* Basic knowledge of SQL and PL/SQL

No prior experience with AI agents, vectors, or embedding models is required—we'll explain everything as we go.

## Estimated Time

* **Lab 1:** 15 minutes
* **Lab 2:** 20 minutes  
* **Lab 3:** 25 minutes
* **Total:** ~60 minutes

## Learn More

* [Oracle Database 26ai Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/26/)
* [DBMS_CLOUD_AI_AGENT Package](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-cloud-ai-agent-package.html)
* [JSON Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/adjsn/)
* [AI Vector Search Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/)

## Acknowledgements

* **Author** - David Start
* **Last Updated By/Date** - David Start, December 2025
