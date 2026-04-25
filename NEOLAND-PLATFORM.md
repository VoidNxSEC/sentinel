# Neoland Platform — Arquitetura Completa

**Status**: Visão arquitetural consolidada  
**Data**: 2026-04-07  
**Escopo**: Plataforma de orquestração AI de alta performance — multi-plataforma, ciclos graduais

---

## Filosofia

**Nix é cidadão de primeira classe — não é o único.**  
A plataforma roda em qualquer ambiente. NixOS é o deployment canônico, mas Linux bare-metal, macOS, Windows (WSL2), Kubernetes e Nomad são alvos igualmente válidos.

**Ciclos graduais.** Nenhuma feature é bloqueante para o próximo ciclo. A plataforma opera e entrega valor em cada estágio antes de avançar.

**Plugin-first desde o design.** Extensibilidade não é um afterthought — é core. Plugins WASM, bibliotecas dinâmicas Rust, scripts Python (PyO3), scripting Lua. Comunidade pode estender sem tocar no core.

**Convergência com o ecossistema descentralizado.** O adr-ledger conecta naturalmente com o que Radicle e o ecossistema Ethereum (Vitalik) já constroem: código soberano, identidade descentralizada (DID), decisões on-chain verificáveis. A plataforma não inventa — ela conecta.

---

## Visão

Neoland não é um app — é uma **plataforma de orquestração AI nível OS**, declarativa, criptograficamente auditável, isolada por design, escalável de um NixOS local até uma fleet de GPUs em qualquer cloud.

Todos os componentes existem. Este documento conecta os pontos e define os ciclos de evolução.

---

## Mapa de Projetos (~/master/)

| Projeto | Papel | Tecnologia | Status |
|---------|-------|-----------|--------|
| `neoland` | Control plane + DSPy pipeline | Rust + Python | Implementando |
| `spectre` | Event bus + Zero-Trust gateway | Rust + NATS | Operacional |
| `adr-ledger` | Ledger criptográfico de decisões | Python + secp256k1 + OPA | Beta |
| `cerebro` | RAG + embeddings | Python | Operacional |
| `phantom` | ML classifier + security scanner | Python + YARA | Operacional |
| `neotron` | Guardrails + agent governance | Python | Em desenvolvimento |
| `neoland-ui` | Dashboard web (API gateway + Next.js) | Bun + Next.js | Planejado |
| `sentinel` | Observabilidade | ? | Existente |
| `securellm-bridge` | LLM proxy Zero-Trust | Rust | Existente |
| `arch-analyzer` | Análise de arquitetura NixOS | ? | Existente |

**Backbone de comunicação:**
- **NATS** (spectre-events) — mensageria assíncrona entre todos os serviços
- **mmap** — IPC zero-copy intra-host entre processos Rust
- **HTTP REST** — interface síncrona para clientes externos
- **WebSocket** — streaming para UI e TUI

---

## Arquitetura Geral

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     INTERFACE LAYER                                     │
│                                                                         │
│  ┌─────────────────────┐         ┌─────────────────────────────────┐   │
│  │   OpenGL TUI (Rust) │         │   neoland-ui (Bun + Next.js)    │   │
│  │   GPU-accelerated   │         │   Dashboard web — sem login      │   │
│  │   glassmorphism     │         │   API Key only                  │   │
│  │   CUDA metrics      │         │   socket.io real-time           │   │
│  └──────────┬──────────┘         └──────────────┬──────────────────┘   │
└─────────────┼─────────────────────────────────────┼────────────────────┘
              │ gRPC / REST                          │ REST / WebSocket
┌─────────────▼─────────────────────────────────────▼────────────────────┐
│                   CONTROL PLANE (neoland :3001)                        │
│                                                                         │
│   Rust — orquestra tudo. Não executa inferência.                       │
│                                                                         │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
│   │ Agent        │  │ Session      │  │ RAG context  │               │
│   │ Orchestrator │  │ Manager (PG) │  │ (cerebro)    │               │
│   └──────┬───────┘  └──────────────┘  └──────────────┘               │
│          │                                                              │
│   ┌──────▼─────────────────────────────────────────────┐              │
│   │              mmap IPC layer                         │              │
│   │   /dev/shm/neoland-<task_id>  (memfd_create)       │              │
│   │   Regions: task_req | jr_out | sr_out | tl_out      │              │
│   └──────────────────────────────────────────────────┘               │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────────┐
│                   PIPELINE LAYER                                        │
│                                                                         │
│   DSPy FastAPI (:8001)  — cada agente em PID namespace próprio         │
│                                                                         │
│   ┌──────────────────────────────────────────────────────────────┐     │
│   │  JUNIOR [PID ns A]  →  SENIOR [PID ns B]  →  ARCHITECT? [C] │     │
│   │      │                     │                     │            │     │
│   │   mmap write            mmap write            mmap write     │     │
│   │   SELinux label         SELinux label         SELinux label  │     │
│   │   NATS publish          NATS publish          NATS publish   │     │
│   └──────────────────────────────────────────────────────────────┘     │
│                              │                                          │
│   ┌──────────────────────────▼───────────────────────────────────┐     │
│   │  TECH-LEADER [PID ns D]  →  ADR generate  →  adr-ledger     │     │
│   └──────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
              │                    │                    │
              ▼                    ▼                    ▼
┌─────────────────┐   ┌────────────────────┐  ┌──────────────────────┐
│  NATS :4222     │   │  adr-ledger        │  │  Phantom :8008       │
│  (spectre)      │   │  secp256k1 sign    │  │  YARA scan           │
│                 │   │  Merkle chain      │  │  pipeline outputs    │
│  Topics:        │   │  OPA policy        │  │  blockOnDetection    │
│  neoland.agent.*│   │  IPFS / S3 / local │  └──────────────────────┘
│  neoland.adr.*  │   │  Radicle DID       │
│  neoland.scan.* │   │  Algorand SBT      │
└─────────────────┘   └────────────────────┘
```

---

## IPC: mmap + Shared Memory

### Design

O control plane Rust cria uma região de memória compartilhada por task via `memfd_create`:

```
/dev/shm/neoland-<task_uuid>
├── Header (64 bytes)
│   ├── version: u8
│   ├── task_id: [u8; 16]  (UUID bytes)
│   ├── stage: u8          (0=pending, 1=junior, 2=senior, 3=architect, 4=tl, 5=done)
│   ├── flags: u32         (bitmap: escalate_architect | phantom_blocked | ...)
│   └── padding: [u8; 43]
│
├── Região TASK_REQ (4 KB)  — escrito pelo control plane, read-only para agentes
├── Região JR_OUT   (8 KB)  — escrito pelo Junior, read-only para Senior+
├── Região SR_OUT   (8 KB)  — escrito pelo Senior, read-only para Architect+
├── Região ARCH_OUT (8 KB)  — escrito pelo Architect (nullable)
└── Região TL_OUT   (16 KB) — escrito pelo TechLeader (inclui ADR draft)
```

**Sincronização:** não usa locks. Control plane escreve `stage` atomicamente. Cada agente espera `stage >= N` antes de ler a região anterior. Python lê via `mmap` module, Rust via `memmap2`.

**NixOS gerencia via `systemd-tmpfiles`:**
```nix
systemd.tmpfiles.rules = [
  "d /dev/shm/neoland 0770 neoland neoland -"
  "f+ /dev/shm/neoland/.keep 0660 neoland neoland -"
];
```

**Tamanho total por task:** ~45 KB — cabe em L3 cache. Zero serialização entre agentes no mesmo host.

---

## NATS — Tópicos (via spectre-events)

Todos os eventos do pipeline publicados no NATS usando o padrão `spectre-events`:

```
neoland.agent.task.started      { task_id, session_id, timestamp }
neoland.agent.junior.done       { task_id, junior_output, confidence, risk_level }
neoland.agent.senior.done       { task_id, senior_output, escalate }
neoland.agent.architect.done    { task_id, architect_output }
neoland.agent.architect.skip    { task_id, reason: "risk_level=low" }
neoland.agent.tl.done           { task_id, decision, adr_title }
neoland.pipeline.complete       { task_id, session_id, checkpoint_path }
neoland.pipeline.error          { task_id, error, stage }

neoland.adr.created             { adr_id, title, status, session_id, storage_backend }
neoland.adr.signed              { adr_id, signature, signer_did }
neoland.adr.anchored            { adr_id, timestamp_proof }

neoland.scan.requested          { task_id, stage, payload_hash }
neoland.scan.result             { task_id, is_threat, threat_level, blocked }
```

O **neoland-ui** subscrive via relay socket.io. A **TUI** subscrive direto via NATS client Rust.

---

## SELinux-Style Labels — Metadados de Segurança dos Agentes

Cada output de agente carrega labels de segurança propagadas pelo pipeline:

```
neoland:agent:junior:risk:medium
neoland:agent:junior:confidence:0.82
neoland:agent:senior:escalated:true
neoland:pipeline:phantom:clean
neoland:pipeline:phantom:blocked       ← bloqueia TechLeader se blockOnDetection
neoland:session:adr:pending-signing
```

**Formato no mmap (Header flags bitmap):**

```rust
bitflags! {
    pub struct PipelineFlags: u32 {
        const PHANTOM_SCAN_REQUESTED = 0x0001;
        const PHANTOM_BLOCKED        = 0x0002;
        const ARCHITECT_REQUIRED     = 0x0004;
        const ARCHITECT_SKIPPED      = 0x0008;
        const HIGH_RISK              = 0x0010;
        const HUMAN_REVIEW_REQUIRED  = 0x0020;
        const ADR_SIGNED             = 0x0040;
        const ADR_ANCHORED           = 0x0080;
        const SESSION_DEGRADED       = 0x0100;  // confidence < warn_threshold por 3+ tasks
    }
}
```

**Enforcement via NixOS + OPA:**
- Labels propagam do Junior até o TechLeader
- Se `PHANTOM_BLOCKED`, o control plane não chama TechLeader e publica `pipeline.error`
- Se `HUMAN_REVIEW_REQUIRED`, decision do TechLeader só persiste após assinatura humana no adr-ledger
- OPA policy avalia as labels antes de cada transição de stage

---

## PID Isolation — Isolamento por Stage

Cada stage do pipeline roda em namespace de PID próprio via `bubblewrap` ou `systemd-run`:

```bash
# Control plane executa cada agente assim:
systemd-run --scope --slice=neoland-agents.slice \
  --property=PIDsMax=50 \
  --property=MemoryMax=512M \
  --property=CPUQuota=50% \
  --property=PrivateTmp=yes \
  --property=NoNewPrivileges=yes \
  python -m neoland_agents.runner --stage junior --task-id <uuid> --mmap-fd <fd>
```

**Por que não containers:** muito overhead para tasks de curta duração (~2-30s). `systemd-run` com cgroups v2 dá isolamento equivalente sem o overhead de imagem/runtime.

**Desafio real:** DSPy carrega o modelo LM config uma vez por processo. Com PID isolation, o `dspy.configure(lm=...)` deve ser feito no `--command runner` antes de executar o agente. A solução é um **pre-fork worker pool**: control plane mantém N workers pre-configurados, um por stage.

```
neoland-agent-worker@junior.service   (pool de 2 workers)
neoland-agent-worker@senior.service   (pool de 2 workers)
neoland-agent-worker@architect.service (pool de 1 worker)
neoland-agent-worker@tech-leader.service (pool de 2 workers)
```

Workers ficam em loop aguardando tasks via NATS (`neoland.agent.junior.task`), escrevem output no mmap, publicam done.

---

## IAM — adr-ledger como Federação de Identidade

O `adr-ledger` já tem a stack completa:
- **Radicle DID** — identidade descentralizada do signer
- **secp256k1** — assinatura criptográfica de cada ADR
- **Merkle tree** — prova de inclusão (ADR X foi incluído no estado Y)
- **OpenTimestamps** — ancoragem temporal
- **Algorand SBT** — Soul-Bound Token como credencial de autoridade
- **OPA Rego** — policy engine para validar quem pode aprovar o quê

**Integração com neoland pipeline:**

```
Task finalizada → TechLeader gera ADR JSON
    ↓
Control plane publica neoland.adr.created
    ↓
adr-ledger recebe via NATS subscriber
    ↓
chain_manager.py assina com secp256k1 do signer DID
    ↓
Adiciona ao Merkle chain
    ↓
Publica para backend configurado: IPFS | S3 | filesystem | Algorand
    ↓
neoland.adr.anchored → timestamp proof
```

**Para enterprise (OIDC / Ory Kratos):**

Ory Kratos gerencia **usuários humanos** (quem pode submeter tasks, quem pode aprovar ADRs high-risk).  
OIDC federation permite que empresas usem seu IdP (Azure AD, Google Workspace, Okta).  
A assinatura no adr-ledger inclui o `sub` claim do OIDC token — ligando identidade corporativa à decisão criptográfica.

```
OIDC IdP (Azure AD)
    ↓
Ory Kratos (session + identity)
    ↓
X-API-Key derivada + DID do usuário
    ↓
Control plane autoriza task
    ↓
ADR assinado com DID do usuário
```

**ADR como federação única:** cada organização que usa neoland tem sua própria Merkle chain. Chains podem ser federadas via Radicle — compartilhando ADRs cross-org sem centralização.

---

## ADR Storage — Agnóstico

Backends suportados pelo adr-ledger (já implementado):

| Backend | Caso de uso | Config |
|---------|-----------|--------|
| Filesystem local | Dev, NixOS single host | `NEOLAND_CHECKPOINT_DIR=/var/lib/neoland/checkpoints` |
| IPFS | Distribuído, imutável, público | `ADR_BACKEND=ipfs` + IPFS daemon |
| S3 / R2 | Enterprise, cloud | `ADR_BACKEND=s3` + credenciais |
| Algorand | Prova on-chain | `ADR_BACKEND=algorand` + wallet |

Search: **ripgrep** para filesystem local, **IPFS DHT** para distribuído, **PostgreSQL full-text** quando indexado.

Binary cache Nix: qualquer usuário da plataforma pode apontar `nix.settings.substituters` para o cache do ecossistema neoland e receber builds pré-compilados sem reconstruir do zero.

---

## OpenGL TUI — Cliente de Alta Performance

**Por que não terminal convencional:** a plataforma é GPU-heavy. Faz sentido ter uma TUI que usa a mesma GPU para renderizar métricas de inferência, confidence bars animadas, o grafo do ecosystem — tudo a 60fps com glassmorphism.

### Rendering: OpenGL + Vulkan

Dois backends explícitos — não uma abstração escondida:

| Backend | Plataforma alvo | Quando usar |
|---------|----------------|------------|
| **Vulkan** | Linux (NixOS, bare-metal), Windows 10+ | Performance máxima, ray tracing futuro |
| **OpenGL 4.6** | macOS (MoltenVK), Linux legacy, VMs | Compatibilidade máxima |
| **CUDA** | NVIDIA em qualquer OS | Compute: inference viz, embeddings, métricas |

**Por que não só wgpu:** wgpu é excelente mas esconde o backend. Para plugin developers e contribuidores de comunidade, a surface API explícita (OpenGL/Vulkan) tem documentação massiva, tutoriais, exemplos. Mercado mais amplo.

**Estratégia de crates:**
```toml
[dependencies]
ash = "0.38"           # Vulkan bindings (raw, zero-overhead)
glow = "0.14"          # OpenGL bindings (portável)
glutin = "0.32"        # Window + context management
cudarc = "0.12"        # CUDA kernels (NVIDIA)
nvidia-ml-sys = "0.8"  # NVML: métricas GPU (VRAM, temp, power)
```

### CUDA — Ecossistema, não só compute

CUDA não é apenas GPU compute — é acesso ao ecossistema:
- **cuBLAS / cuDNN**: operações de tensor para visualização de embeddings em tempo real
- **TensorRT**: executar modelos diretamente na TUI (preview de inferência local)
- **NCCL**: multi-GPU quando expandir para fleet
- **NVIDIA NVML**: métricas de hardware (VRAM, temperatura, power draw, SM utilization)
- **Developer mindshare**: o dev de ML pensa em CUDA — a TUI precisa falar essa língua

### Plugin System

Extensibilidade em 3 camadas:

```
┌─────────────────────────────────────────────────────────────────┐
│  Core (Rust — compile-time)                                     │
│  Pipeline, mmap, NATS, IAM, ADR rendering                       │
└─────────────────────────────────────────────────────────────────┘
              ↑ plugin trait boundary
┌─────────────────────────────────────────────────────────────────┐
│  Native Plugins (Rust .so/.dll — dlopen)                        │
│  Custom agent stages, custom renderers, exchange integrations   │
│  Performance máxima, acesso direto à GPU                        │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  WASM Plugins (wasmtime — sandboxed)                            │
│  Custom pipeline steps, formatters, validators                  │
│  Distribuição segura: qualquer linguagem → WASM                 │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  Script Plugins (Lua via mlua — lightweight)                    │
│  Keybindings, automações, UI tweaks, config dinâmica            │
│  Zero recompile — live reload                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Plugin trait (Rust):**
```rust
pub trait NeolandPlugin: Send + Sync {
    fn name(&self) -> &str;
    fn version(&self) -> semver::Version;

    // Hooks opcionais — implementa só o que precisa
    fn on_agent_done(&self, stage: AgentStage, output: &AgentOutput) -> PluginResult { Ok(()) }
    fn on_adr_created(&self, adr: &ADRDocument) -> PluginResult { Ok(()) }
    fn render_panel(&self, ctx: &RenderCtx) -> Option<Panel> { None }
    fn on_nats_event(&self, subject: &str, payload: &[u8]) -> PluginResult { Ok(()) }
}
```

**Exemplos de plugins de comunidade:**
- `neoland-plugin-grafana` — push de métricas para Grafana
- `neoland-plugin-slack` — notificação quando TL decide REJECT
- `neoland-plugin-ipfs-viz` — visualizar o Merkle tree do adr-ledger
- `neoland-plugin-tensor-viz` — embedding space 3D no painel CUDA

### Layout TUI

```
┌─────────────────────────────────────────────────────────────────────────┐
│  neoland  ●  control plane UP  ●  DSPy UP  ●  NATS UP         [q]uit  │
├──────────┬──────────────────────────────────────────────────────────────┤
│          │                                                              │
│ [P]ipeline│  ┌─ Task Input ────────────────────────────────────────┐   │
│ [S]essions│  │ > refactor auth middleware to use JWT RS256          │   │
│ [A]DRs    │  └─────────────────────────────────────────────────────┘   │
│ [G]raphs  │                                                            │
│ [C]onfig  │  ┌─ JUNIOR ─────┐  ┌─ SENIOR ─────┐  ┌─ TECH-LEADER ──┐ │
│ [+]Plugins│  │ ◉ running    │  │ ○ waiting    │  │ ○ waiting     │ │
│           │  │ conf: ████░  │  │              │  │               │ │
│           │  │ risk: MEDIUM │  │              │  │               │ │
│           │  └──────────────┘  └──────────────┘  └───────────────┘ │
│           │                                                            │
│           │  ┌─ GPU ────────────────┐  ┌─ NATS stream ────────────┐  │
│           │  │ VRAM  ████████░ 7.2G │  │ agent.junior.done 14:33  │  │
│           │  │ Util  ███░░░░░  34%  │  │ agent.senior.task 14:33  │  │
│           │  │ Temp  68°C 142W      │  │ scan.result clean 14:33  │  │
│           │  └──────────────────────┘  └──────────────────────────┘  │
└──────────┴──────────────────────────────────────────────────────────────┘
```

### Glassmorphism — Shaders

```glsl
// Fragment shader (OpenGL GLSL 460) — painel glassmorphism
#version 460 core

uniform sampler2D u_backdrop;    // framebuffer capturado atrás do painel
uniform float u_blur_radius;     // 12.0 default
uniform vec4  u_tint;            // vec4(0.08, 0.08, 0.12, 0.80)
uniform float u_border_alpha;    // 0.18

in vec2 v_uv;
out vec4 frag_color;

vec4 gaussian_blur_13(sampler2D tex, vec2 uv, float radius) {
    // 13-tap Gaussian kernel
    vec4 result = vec4(0.0);
    float weights[7] = float[](0.2270, 0.1945, 0.1216, 0.0540, 0.0162, 0.0032, 0.0004);
    vec2 texel = 1.0 / vec2(textureSize(tex, 0));
    for (int i = -6; i <= 6; i++) {
        result += texture(tex, uv + vec2(i, 0) * texel * radius) * weights[abs(i)];
    }
    return result;
}

void main() {
    vec4 blurred = gaussian_blur_13(u_backdrop, v_uv, u_blur_radius);
    vec4 glass = mix(blurred, u_tint, u_tint.a);

    // Border glow
    vec2 border = smoothstep(0.0, 0.003, v_uv) * smoothstep(0.0, 0.003, 1.0 - v_uv);
    float border_mask = 1.0 - min(border.x, border.y);
    glass.rgb += vec3(border_mask * u_border_alpha);

    frag_color = glass;
}
```

**Vulkan equivalente:** renderpass com input attachment para o backdrop, compute shader para blur.

---

## Kubernetes / Nomad — Alta Escala

### Kubernetes (NVIDIA Inception GPU fleet)

Cada serviço do ecossistema tem um Helm chart correspondente.  
O `spectre` já tem Helm chart (`~/master/spectre/charts/`).

**Mapeamento NixOS → Kubernetes:**

| NixOS option | Kubernetes equivalente |
|-------------|----------------------|
| `MemoryMax` | `resources.limits.memory` |
| `CPUQuota` | `resources.limits.cpu` |
| `gpu.enable` | `resources.limits."nvidia.com/gpu": 1` |
| `gpu.runtimeClass` | `spec.runtimeClassName: nvidia` |
| `replicaCount` | `spec.replicas` |
| `services.*.url` | `env.SERVICE_URL` via ConfigMap |

**NATS em Kubernetes:** NATS operator via Helm, JetStream habilitado para persistência de eventos.

**mmap em Kubernetes:** substituído por NATS JetStream (mmap é intra-host). Em cluster multi-node, a comunicação entre stages passa pelo NATS. Em single-node (mesmo Pod), mmap via `emptyDir: medium: Memory`.

### Nomad

Alternativa mais simples ao Kubernetes para fleets menores.  
Nomad suporta `task.resources.memory`, `task.resources.cpu`, drivers `exec` e `docker`.  
NATS via Nomad service discovery.

A escolha Kubernetes vs Nomad é declarada em `ecosystem.nix`:
```nix
ai.ecosystem.deploymentMode = "kubernetes";  # ou "nomad" ou "nixos"
```

---

## Fluxo Completo — Task End-to-End

```
1. Usuário submete task via TUI ou neoland-ui
   → POST :3001/v1/agents/task { task, session_id }

2. Control plane:
   a. Busca RAG context no cerebro (top-5 docs, 500 chars each)
   b. Cria mmap region: /dev/shm/neoland-<task_id>
   c. Escreve TASK_REQ na região
   d. Publica neoland.agent.task.started no NATS

3. Junior worker (PID ns A) recebe via NATS:
   a. Lê TASK_REQ do mmap
   b. Executa DSPy ChainOfThought(TaskProposal)
   c. dspy.Assert(confidence in [0,1])
   d. dspy.Assert(risk_level in ["low","medium","high"])
   e. Escreve JR_OUT no mmap + seta stage=2
   f. Publica neoland.agent.junior.done

4. Phantom scan (async, se habilitado):
   a. Recebe neoland.scan.requested
   b. YARA scan no JR_OUT
   c. Publica neoland.scan.result
   d. Se blocked → set PHANTOM_BLOCKED flag no mmap header

5. Senior worker (PID ns B) recebe neoland.agent.junior.done:
   a. Verifica flag PHANTOM_BLOCKED → aborta se true
   b. Lê JR_OUT do mmap
   c. Executa DSPy ChainOfThought(SeniorCritique)
   d. Se escalate_to_architect → set ARCHITECT_REQUIRED flag
   e. Escreve SR_OUT + stage=3
   f. Publica neoland.agent.senior.done

6. Architect (condicional, PID ns C):
   a. Só executa se ARCHITECT_REQUIRED flag
   b. Escreve ARCH_OUT + stage=4
   c. Publica neoland.agent.architect.done

7. TechLeader (PID ns D):
   a. Lê JR_OUT + SR_OUT + ARCH_OUT (opcional)
   b. Executa DSPy ChainOfThought(TechLeaderDecision)
   c. Gera ADR draft no TL_OUT
   d. Escreve stage=5 (done)
   e. Publica neoland.agent.tl.done

8. adr-ledger recebe neoland.agent.tl.done:
   a. chain_manager.py lê TL_OUT via API
   b. Assina ADR com secp256k1 do DID configurado
   c. Adiciona ao Merkle chain
   d. Persiste no backend configurado (IPFS/S3/filesystem)
   e. Publica neoland.adr.created + neoland.adr.signed

9. Control plane:
   a. Persiste resultado no PostgreSQL (agent_sessions)
   b. Libera mmap region
   c. Responde ao cliente com PipelineResult

10. TUI/UI recebe pipeline_done via NATS/WebSocket
    a. Renderiza decision badge final
    b. Link para ADR no vault
```

---

## NixOS — Orquestração

O NixOS gerencia toda a plataforma de forma declarativa:

```nix
# /etc/nixos/modules/ai/neoland/platform.nix (futuro)

{
  # NATS via spectre
  services.nats.enable = true;
  services.nats.jetstream = true;

  # mmap regions
  systemd.tmpfiles.rules = [
    "d /dev/shm/neoland 0770 neoland neoland 1h"
  ];

  # Agent worker pools
  systemd.services."neoland-agent-worker@" = {
    # template unit — instanciado para cada stage
  };

  # Pipeline
  services.neoland-dspy-pipeline.enable = true;

  # Control plane
  services.neoland-control-plane.enable = true;

  # adr-ledger subscriber
  services.adr-ledger-subscriber.enable = true;
  services.adr-ledger-subscriber.natsUrl = "nats://localhost:4222";
  services.adr-ledger-subscriber.backend = "ipfs";  # filesystem | ipfs | s3

  # Binary cache
  nix.settings.substituters = [
    "https://neoland.cachix.org"
    "https://cache.nixos.org"
  ];
}
```

---

## Fases de Implementação — Plataforma

### Fase A — IPC Layer (mmap + NATS integration) [ ]
- [ ] `src/agents/mmap.rs` — criar/ler/escrever regiões mmap no control plane
- [ ] `src/agents/flags.rs` — PipelineFlags bitflags
- [ ] NATS publisher no control plane (usar spectre-events crate)
- [ ] NATS subscriber nos agent workers Python
- [ ] Worker pool systemd template units (NixOS)
- [ ] Testes: roundtrip mmap Rust → Python → Rust

### Fase B — adr-ledger Integration [ ]
- [ ] NATS subscriber no adr-ledger para `neoland.agent.tl.done`
- [ ] Adapter: TL_OUT JSON → adr-ledger schema
- [ ] Backend switcher: filesystem | IPFS | S3
- [ ] Publicar `neoland.adr.signed` após assinatura
- [ ] Testes: ADR gerado pelo pipeline → assinado → verificável

### Fase C — Phantom Integration [ ]
- [ ] NATS subscriber no phantom para `neoland.scan.requested`
- [ ] YARA scan em payloads de pipeline (não só emails)
- [ ] Publicar `neoland.scan.result` + set PHANTOM_BLOCKED via API
- [ ] Testes: payload com secret → pipeline bloqueado

### Fase D — neoland-ui [ ]
(Ver `~/master/neoland-ui/NEOLAND-UI.md` para detalhe completo)
- [ ] Setup base (copiar archive, configurar Bun)
- [ ] API gateway com rotas neoland (sem login — API key only)
- [ ] Pipeline live view via socket.io
- [ ] ADR Vault (agnostic: filesystem | IPFS | S3)
- [ ] Ecosystem map com react-flow
- [ ] Sessions + Agents + Settings

### Fase E — OpenGL TUI (neochat-tui) [ ]
- [ ] Novo projeto Rust em `~/master/neochat-tui/`
- [ ] wgpu backend com glassmorphism shaders
- [ ] NATS client direto (spectre-events)
- [ ] Layout: pipeline live, GPU metrics, NATS event stream
- [ ] CUDA bindings para métricas GPU (nvidia_cuda-sys)
- [ ] NixOS package derivation

### Fase F — IAM (Ory Kratos + OIDC) [ ]
- [ ] Ory Kratos deploy via NixOS module
- [ ] OIDC provider config (Google, Azure AD, Okta)
- [ ] DID derivado de OIDC `sub` claim
- [ ] ADR signed com DID do usuário OIDC
- [ ] NixOS module: `services.neoland-iam`

### Fase G — Kubernetes / Nomad [ ]
- [ ] Helm charts para cada serviço (base no spectre charts existente)
- [ ] NATS JetStream em cluster
- [ ] mmap → shared emptyDir (intra-pod) ou NATS (inter-pod)
- [ ] GPU fleet config (NVIDIA Inception — runtimeClass: nvidia)
- [ ] KEDA autoscaling baseado em NATS queue depth

---

## Binary Cache

Qualquer usuário da plataforma pode usar:

```nix
nix.settings = {
  substituters = [ "https://neoland.cachix.org" ];
  trusted-public-keys = [ "neoland.cachix.org-1:<public-key>" ];
};
```

Setup: `cachix` ou `attic` (self-hosted) rodando em NixOS com módulo dedicado.  
CI/CD push automático dos builds para o cache após cada merge na main.

---

## Decisões Fixadas

| Decisão | Escolha | Razão |
|---------|---------|-------|
| TUI render | OpenGL 4.6 + Vulkan (explícito) | Mercado amplo, DX rico, documentação massiva |
| CUDA | Suportado (cudarc + nvml) | Ecossistema NVIDIA, tensor viz, métricas GPU |
| Plugin system | WASM + .so nativo + Lua | 3 camadas: segurança / performance / agilidade |
| Nix | Primeira classe, não único | Cross-platform desde o design |
| IAM | adr-ledger DID + OIDC (Fase F) | API key primeiro, federação depois |
| mmap | Intra-host + NATS inter-host | Zero-copy local, mensageria distribuída |
| PID isolation | systemd-run template units | NixOS nativo, zero overhead de container |
| ADR storage | Agnostic: filesystem / IPFS / S3 / Algorand | adr-ledger já implementa |
| ADR search | ripgrep (local) + IPFS DHT (distribuído) | Agnóstico de backend |
| Auth UI | API Key only — sem login/sessão | Complexidade zero na UI |
| K8s vs Nomad | Kubernetes primário | NVIDIA Inception + ecossistema maior |
| Ciclos | Gradual, a plataforma entrega em cada ciclo | Não bloquear em perfeccionismo |

---

## Modelo de Ciclos

A plataforma não tem uma "versão final" — evolui em ciclos, cada um entregando valor real.

```
Ciclo 0 — Core funcionando (ATUAL)
  neoland control plane + DSPy pipeline + PostgreSQL
  4 agentes + checkpoint ADR em filesystem
  neoland-ui básico (pipeline runner + sessions)

Ciclo 1 — Integração do ecossistema
  NATS via spectre-events no control plane
  adr-ledger subscriber (NATS → sign → persist)
  Phantom integrado (NATS scan)
  mmap IPC intra-host

Ciclo 2 — TUI e observabilidade
  neochat-tui OpenGL MVP (pipeline live, GPU metrics)
  Glassmorphism shaders
  NATS stream direto na TUI

Ciclo 3 — Plugin system
  Plugin trait + dlopen para .so nativo
  wasmtime para WASM plugins
  Lua scripting (mlua)
  Primeiro plugin de comunidade

Ciclo 4 — IAM e federação
  Ory Kratos + OIDC
  DID derivado de OIDC sub
  ADR assinado com identidade corporativa
  Radicle federation entre orgs

Ciclo 5 — Fleet e escala
  Kubernetes Helm charts (base spectre)
  NATS JetStream em cluster
  GPU fleet (NVIDIA Inception)
  KEDA autoscaling por queue depth NATS

Ciclo 6 — CUDA + Vulkan
  neochat-tui Vulkan backend
  CUDA tensor viz (embedding space 3D)
  TensorRT plugin para inferência local na TUI

Ciclo N — Ecossistema
  Plugins de comunidade
  Binary cache público
  Radicle DID federation cross-org
  On-chain ADR anchoring (Algorand / Ethereum)
```

**Regra dos ciclos:** cada ciclo é independente. O sistema roda e entrega valor ao final de cada um. Nenhum ciclo é pré-requisito absoluto do próximo — são melhorias incrementais sobre uma base sólida.

---

## Conexão com Ecossistema Descentralizado

O que Radicle e o ecossistema Ethereum já constroem converge diretamente com a plataforma:

- **Radicle Sovereign Code** → código hospedado de forma soberana, Radicle DID para identidade de devs — o adr-ledger já usa Radicle DID
- **Vitalik / Ethereum** → decisões on-chain verificáveis, ZK proofs, governança descentralizada — o adr-ledger já integra Algorand SBT e está preparado para Ethereum
- **ADR como prova de decisão** → cada decisão arquitetural assinada, Merkle-proofed, timestamped — qualquer auditoria pode verificar sem confiar no operador
- **Futuro**: ADRs como governança on-chain — uma organização vota em ADRs via Ethereum/Algorand, a decisão é criptograficamente vinculada ao código no Radicle

Esta convergência não é planejada — é natural. A plataforma seguiu os princípios corretos e chegou ao mesmo lugar que os maiores projetos de infraestrutura descentralizada.

---

*Última atualização: 2026-04-07 — Decisões de rendering, CUDA, plugins e ciclos consolidadas. Implementação: Ciclo 0 em andamento.*
