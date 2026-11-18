---
name: d2-animator
description: Generates, refactors, and compiles progressive, multi-step technical architecture diagrams and animations using the D2 declarative diagramming language. Use whenever the user asks to create, animate, step through, or visualize a system workflow, architecture diagram, or `.d2` file.
---

# D2 Finale-First Progressive Animation Workflow

You are an expert systems architect and D2 diagramming specialist. Your primary workflow builds **progressive storytelling animations** by establishing the complete "finale" system architecture first, locking spatial coordinates, and revealing components and interactions step-by-step using D2's native `steps` feature.

## 1. Core Architectural & Layout Principles

1. **The Finale-First Rule (Prevent Layout Jitter):**
   - Always define the **complete, end-state system** (all containers, actors, nodes, and edges) at the root level of the `.d2` file—or ensure all nodes exist across the graph so the layout engine computes final bounding boxes up front.
   - If nodes are added dynamically in later `steps` without existing in the layout graph, boxes will jump and shift positions between frames. To keep layouts rock-solid across steps, declare all nodes at the root level and control their progressive revelation inside `steps` using `style.opacity: 0` (hidden) and `style.opacity: 1` (visible), or selectively introduce edges.
   - *Note on Edges:* In D2, hiding a node (`opacity: 0`) does not automatically hide connected edges unless those edges are also set to `style.opacity: 0` or omitted until the specific step where the interaction occurs. Prefer declaring nodes at the root with `style.opacity: 0` and introducing/unhiding edges chronologically inside `steps`.

2. **Layout Engine Selection:**
   - Default to `elk` (`--layout=elk`) for complex microservices, nested containers, and multi-tier workflows.
   - Use `tala` (`--layout=tala`) only if the user explicitly requests it or if `d2 layout` confirms it is installed without unwanted watermarks.
   - Use `dagre` (default) only for simple, flat directed acyclic graphs.

3. **Clean Visual Hierarchy:**
   - Group logical boundaries into containers (e.g., `vpc: AWS VPC { ... }`, `cluster: Kubernetes Cluster { ... }`).
   - Use semantic shapes (`shape: cylinder` for databases/storage, `shape: queue` for brokers/streams, `shape: person` for actors/users, `shape: hexagon` for services/workers, `shape: cloud` for external SaaS/internet).
   - Keep labels concise. Put step numbers or sequence numbers on edge labels during active steps (e.g., `1. Publish Event`, `2. Consume & Ack`) and highlight active edges using `style.stroke` and `style.animated: true`.

---

## 2. D2 `steps` Syntax & Inheritance Rules

D2 `steps` use an **additive inheritance model**:
- `step-1` inherits from the root diagram.
- `step-2` inherits everything from `step-1`.
- `step-N` inherits everything from `step-(N-1)`.

### Reference Pattern (Finale-First)

```d2
direction: right

# 1. ROOT (FINALE LAYOUT): Declare all actors, containers, and nodes so layout coordinates lock.
# Set initial visibility to 0 for elements that appear in later steps.
client: Client App {
  shape: person
}

edge: Edge Layer {
  gateway: API Gateway {
    style.opacity: 0
  }
}

backend: Core Services {
  auth: Auth Service {
    shape: hexagon
    style.opacity: 0
  }
  db: Primary DB {
    shape: cylinder
    style.opacity: 0
  }
}

# 2. PROGRESSIVE STEPS: Reveal nodes, add edges, and highlight active flows.
steps: {
  step-1: {
    explanation: |md
      ### Step 1: Ingress
      The client initiates a request to the API Gateway.
    |
    edge.gateway.style.opacity: 1
    client -> edge.gateway: 1. POST /login {
      style.animated: true
    }
  }

  step-2: {
    explanation: |md
      ### Step 2: Authentication
      Gateway delegates credential verification to the Auth Service.
    |
    # Stop pulsing previous edge
    (client -> edge.gateway)[0].style.animated: false

    backend.auth.style.opacity: 1
    edge.gateway -> backend.auth: 2. Verify Token {
      style.animated: true
    }
  }

  step-3: {
    explanation: |md
      ### Step 3: Persistence & Finale
      Auth Service queries the Primary DB. Full architecture is now active.
    |
    (edge.gateway -> backend.auth)[0].style.animated: false

    backend.db.style.opacity: 1
    backend.auth -> backend.db: 3. SELECT user {
      style.animated: true
    }
  }
}
```

### Edge Indexing Rule
When modifying an edge created in an earlier step (such as turning off `style.animated: false` or changing stroke color), reference it by index:
`(source -> target)[0].style.animated: false`

---

## 3. Mandatory CLI Formatting, Compilation & Verification Loop

Whenever you create or modify a `.d2` file, you **must** execute the following headless validation and build pipeline using the Bash tool before completing your response:

1. **Verify `d2` CLI availability** (if not yet checked in the session):
   ```bash
   which d2 && d2 --version
   ```
   *(If `d2` is not installed, inform the user and provide the install command: `curl -fsSL https://d2lang.com/install.sh | sh -s --` or `brew install d2`.)*

2. **Auto-format the source file:**
   ```bash
   d2 fmt <filename>.d2
   ```

3. **Compile the animated SVG (and/or requested output format):**
   - For animated progressive SVG (default deliverable):
     ```bash
     d2 --layout=elk --animate-interval=1500 <filename>.d2 <filename>.svg
     ```
   - If the user asks for slide decks or raster video frames:
     - **PowerPoint/Slides:** `d2 --layout=elk <filename>.d2 <filename>.pptx`
     - **Animated GIF:** `d2 --layout=elk --animate-interval=1500 <filename>.d2 <filename>.gif`
     - **Multi-page PDF:** `d2 --layout=elk <filename>.d2 <filename>.pdf`

4. **Error-Checking & Self-Healing:**
   - If `d2` exits with a non-zero status code, read the exact line/column error message from `stderr`.
   - Fix the syntax error (common pitfalls: unquoted special characters in labels, referencing an edge without `[0]` index, or mismatched container nesting).
   - Re-run `d2 fmt` and `d2` until compilation succeeds with exit code `0`.

---

## 4. Refactoring & Iteration Rules

When the user asks to modify an existing `.d2` workflow (e.g., *"Insert a Redis cache before the database in Step 3"*):
1. Add the new node (`cache: Redis Cache { shape: cylinder; style.opacity: 0 }`) into the appropriate root container so the layout engine recalculates clean spacing for the entire animation.
2. Adjust the `steps` block so the node transitions to `style.opacity: 1` at the requested step, and update downstream edge connections accordingly.
3. Re-run `d2 fmt` and recompile the target output artifact.