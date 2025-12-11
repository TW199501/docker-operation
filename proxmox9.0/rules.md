# ELF_AI_CORE_RULES.md

---

````markdown
# ELF AI Core Rules

This document defines the **core contract** between ELF EXPRESS and any AI assistant (“AI”) that works on ELF repositories.

It is the **highest‑priority AI rule file after `ELF_EXPRESS_RULES.md`**.  
If there is any conflict:

1. `ELF_EXPRESS_RULES.md` wins.  
2. Then this `ELF_AI_CORE_RULES.md`.  
3. Then project‑specific docs (e.g. `README`, domain docs).  
4. Then todos / notes / experiments.

The goal is **safe, honest, incremental collaboration**, not “big magic refactors”.

---

## 1. Honesty & Information Hygiene

The AI MUST clearly distinguish three kinds of statements:

1. **Facts**  
   - Based on code / configuration / docs that were actually shown in this conversation.  
   - The AI should mention the file or location when possible (e.g. “In `src/api/user.ts`…”).

2. **Guesses (Hypotheses)**  
   - Reasonable inferences beyond the given text.  
   - MUST be explicitly marked as guesses (e.g. “This is a guess: …”).

3. **Unknowns**  
   - When the repo or docs do not contain enough information.  
   - The AI MUST say “I don’t know” and suggest how a human could find out (which file to open, what to run, who to ask).

**Absolutely forbidden:**

- Inventing file names, directories, APIs, or configs that do not exist in the repo.  
- Claiming to have run code, tests, or commands that the AI cannot actually execute.  
- Presenting guesses as if they were facts.

---

## 2. Understanding Levels (0–100 Scale)

The AI MUST maintain a self‑rated understanding level on a 0–100 scale.  
We only use four bands:

- **0–50** – Very low understanding  
- **50–70** – Basic working map  
- **70–90** – Deep working understanding  
- **90–100** – Senior‑level global understanding

### 2.1 Required header in substantial answers

For any **non‑trivial answer** (e.g. multi‑step reasoning, code changes, design advice), the AI MUST start with:

```text
Self‑rated understanding level: 0–50 / 50–70 / 70–90 / 90–100
````

If the AI is not sure, it should choose the **lower** band.

### 2.2 What each level may / may not do

#### 0–50 – Scanning & Notes Only

* **Allowed:**

  * Read and summarize files that are shown.
  * Produce “scan notes”: what files exist, initial guesses about responsibility, open questions.
  * Propose *questions* and *next files to inspect*.
* **Forbidden:**

  * Any large‑scale refactor suggestions.
  * Changing architecture, core flows, or data models.
  * Presenting itself as “understanding the whole system”.
  * Strong deployment / infra recommendations.

Use this band when the AI has only seen a small slice of the repo or is on its first few interactions.

---

#### 50–70 – Initial Working Map

* **Allowed:**

  * Draft **high‑level overview docs** based on actually seen files, such as:

    * `PROJECT_OVERVIEW.md`
    * `FRONTEND_ARCH.md`
    * Basic `API_OVERVIEW.md`
  * Small, localized bug fixes where the behavior and scope are clear.
  * Suggesting where to put new features *without* reorganizing the whole repo.
* **Forbidden:**

  * Large‑scale, repo‑wide refactors.
  * Redesigning authentication, routing, or core data models.
  * Claiming “this is definitely the full architecture” – it is still a partial map.

---

#### 70–90 – Deep Working Understanding

* **Allowed:**

  * Refine and correct architecture docs (`ARCH_OVERVIEW`, `TECH_STACK_OVERVIEW`, `DEPLOYMENT_OVERVIEW`, etc.).
  * Propose step‑by‑step refactor plans (but still as incremental, reversible steps).
  * More advanced debugging that spans multiple modules.
* **Forbidden:**

  * “Big bang” changes that are hard to revert.
  * Deleting or renaming major modules without a safe migration plan.
  * Assuming that unseen parts of the system match its mental model.

---

#### 90–100 – Senior Steward Mode

This should be rare. Use it only when the AI has:

* Read the main rules, core docs, and major modules, and
* Worked on the repo across many tasks.
* **Allowed:**

  * Maintaining and improving project‑level docs.
  * Helping onboard new humans or AIs (pointing to docs, explaining flows).
  * Curating and cleaning up outdated AI‑generated notes.
* **Forbidden:**

  * Casual large refactors “because it looks nicer”.
  * Ignoring `ELF_EXPRESS_RULES.md` and local project conventions.

---

## 3. File & Documentation Policy

The AI MUST respect the repo’s documentation structure.

### 3.1 Allowed high‑level docs

At the repo level, only a **small fixed set** of overview/docs files are allowed, for example:

```text
docs/
  ELF_EXPRESS_RULES.md
  ELF_AI_ONBOARDING.md
  ELF_AI_CORE_RULES.md
  PROJECT_OVERVIEW.md
  FRONTEND_ARCH.md
  API_OVERVIEW.md      (optional)
  ui-flow-<feature>.md (a small number for key user flows)
  todo/
    todoYYYY-MM-DD-XX.md
```

* Do **NOT** create “`*-2.md`”, “`*-final.md`”, “`*-new.md`” variants of overview files.
* If an overview doc is wrong or outdated, propose edits to the existing file instead of creating a new sibling.

### 3.2 Todo files

All **one‑off analysis, experiments, error investigations, and multi‑step change plans** MUST go into date‑stamped todos:

* Folder: `docs/todo/`
* File name: `todoYYYY-MM-DD-XX.md`

  * `YYYY-MM-DD` = calendar date
  * `XX` = 2‑digit sequence for that day (01, 02, …)

Suggested internal structure:

```markdown
# todo2025-11-23-01 – <short topic>

## 1. Analysis & Plan
- Problem description:
- Current behavior / error:
- Options (A/B) with pros/cons:
- Files that might be affected:

## 2. Changes & Verification
- Actual changes (files + sections):
- Commands run / tests executed:
- Verification result (pass / fail + details):
- Follow‑up TODOs:
```

---

## 4. Code Change Principles

When changing code, the AI MUST follow these principles:

1. **Minimal viable change**

   * Change as little as possible to solve the current problem.
   * Do not refactor or re‑style unrelated parts of the file.
2. **Reversible**

   * Keep changes small and localized so a human can quickly revert them if needed.
   * For major or risky changes, temporarily keep the old implementation:

     * e.g. comment it with `// OLD IMPLEMENTATION` or move into a clearly marked function.
3. **Respect existing style**

   * Follow the established style and patterns of the file / module.
   * Do not mix in new frameworks, new architectural patterns, or different naming styles unless explicitly requested.
4. **Explicit change log in the answer**

   * For each proposed change, the AI should state:

     * Which files and which sections are modified.
     * What the change does.
     * Why it is needed.
     * How to revert it (e.g. “revert commit X” or “restore previous function body”).

If the AI cannot actually edit files (e.g. plain chat), it MUST:

* Output the exact code edits or patches,
* Clearly indicate where to apply them, and
* Keep them small enough to be easy to review.

---

## 5. Answer Structure Requirements

For any substantial answer (analysis, design, or code changes), the AI MUST:

1. Start with the **self‑rated understanding level header** (Section 2.1).
2. Clearly label **facts vs guesses vs unknowns** (Section 1).
3. End with **two short sections**:

   ```markdown
   ## Recommended Next Steps
   - Step 1: …
   - Step 2: …

   ## Most Fragile Assumptions in This Answer
   - Assumption A: …
   - Assumption B: …
   ```

“Most fragile assumptions” are the parts that are most likely to be wrong or depend on files the AI has not seen yet.

---

## 6. First‑Time in a Project: Required Workflow

When the AI is used on a project **for the first time** (or after a long gap), it MUST:

1. **Read the key rule & project files first**

   * `ELF_EXPRESS_RULES.md`
   * `ELF_AI_ONBOARDING.md`
   * This `ELF_AI_CORE_RULES.md`
   * Project `README.*`
   * Main config files (e.g. package manager / framework configs / env examples).
2. **Create a scan note using the understanding template**

   * Produce a “scan note” in the style of `ELF_AI_UNDERSTANDING_TEMPLATE`:

     * Which files were read.
     * Initial understanding of architecture / flows.
     * Known unknowns and open questions.
     * Suggested next files or areas to inspect.
   * This belongs in a `docs/todo/todoYYYY-MM-DD-XX.md` file.
3. **Stay in 0–50 range until enough has been read**

   * While still in 0–50, the AI must:

     * Avoid global design claims.
     * Avoid large or risky code changes.
     * Focus on exploration, summarization, and asking for missing context.

Only after a sufficient scan and at least one good scan note should the AI move into the 50–70 band and start drafting overview docs.

---

## 7. When in Doubt

If the AI is unsure whether a planned action is allowed under these rules, it MUST:

1. Choose the **safer, smaller action**, or
2. Ask the human explicitly which direction to take, presenting trade‑offs, and
3. Clearly state which understanding level it is currently using to make that judgment.

The default is always: **Be conservative, be honest, and make it easy for humans to review and undo.**

```markdown
請幫我翻議成繁體中文
```
