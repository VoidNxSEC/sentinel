/*
 * Neoland Agent Pipeline — YARA Detection Rules
 *
 * Targets: ADR checkpoint files, DSPy pipeline artifacts, agent output.
 * Complements SIGMA rules in sigma/neoland/agent_pipeline_anomalies.yml.
 *
 * Author:  VoidNxLabs SOC
 * Date:    2026-04-07
 * Version: 1.0
 */

rule Neoland_ADR_PromptInjection : neoland injection
{
    meta:
        description = "Detects prompt injection payloads embedded in ADR checkpoint JSON files"
        author      = "VoidNxLabs SOC"
        date        = "2026-04-07"
        severity    = "high"
        mitre       = "T1059.006"  // Command and Scripting Interpreter: Python
        reference   = "neoland pipeline — checkpoint path traversal via crafted LLM output"

    strings:
        $adr_marker = "\"adr_id\"" ascii
        $inj1 = "ignore previous instructions" ascii nocase
        $inj2 = "disregard all prior" ascii nocase
        $inj3 = "system prompt:" ascii nocase
        $inj4 = "```python" ascii
        $inj5 = "```bash" ascii
        $inj6 = "__import__(" ascii
        $inj7 = "eval(" ascii
        $inj8 = "exec(" ascii
        $inj9 = "os.system(" ascii
        $inj10 = "subprocess.run(" ascii
        $inj11 = "subprocess.Popen(" ascii

    condition:
        $adr_marker and any of ($inj*)
}

rule Neoland_ADR_ShellPayload : neoland execution
{
    meta:
        description = "Detects shell command payloads in ADR action_items or decision fields"
        author      = "VoidNxLabs SOC"
        date        = "2026-04-07"
        severity    = "critical"
        mitre       = "T1059.004"  // Unix Shell

    strings:
        $adr_marker = "\"adr_id\"" ascii
        $sh1 = /\bcurl\s+(-[a-zA-Z]+\s+)*https?:\/\// ascii
        $sh2 = /\bwget\s+(-[a-zA-Z]+\s+)*https?:\/\// ascii
        $sh3 = /\|[\s]*bash/ ascii
        $sh4 = /\|[\s]*sh\b/ ascii
        $sh5 = "chmod +x" ascii
        $sh6 = "/dev/tcp/" ascii
        $sh7 = "nc -e" ascii
        $sh8 = "mkfifo" ascii
        $sh9 = "base64 -d" ascii

    condition:
        $adr_marker and any of ($sh*)
}

rule Neoland_Checkpoint_PathTraversal : neoland evasion
{
    meta:
        description = "Detects path traversal sequences in checkpoint filenames or content"
        author      = "VoidNxLabs SOC"
        date        = "2026-04-07"
        severity    = "high"
        mitre       = "T1036"  // Masquerading

    strings:
        $adr_marker = "\"adr_id\"" ascii
        $trav1 = "../" ascii
        $trav2 = "..%2f" ascii nocase
        $trav3 = "%2e%2e/" ascii nocase
        $trav4 = /\\\.\\\.\\\\/ ascii  // ..\\ on Windows-compat paths
        $trav5 = "/etc/passwd" ascii
        $trav6 = "/etc/shadow" ascii
        $trav7 = "/proc/self" ascii

    condition:
        $adr_marker and any of ($trav*)
}

rule Neoland_Pipeline_SuspiciousConfidence : neoland manipulation
{
    meta:
        description = "Detects manipulated confidence values in pipeline JSON output (NaN/Infinity injection)"
        author      = "VoidNxLabs SOC"
        date        = "2026-04-07"
        severity    = "medium"
        mitre       = "T1565.001"  // Data Manipulation: Stored Data

    strings:
        $conf_field = "\"confidence\"" ascii
        $nan1 = "NaN" ascii
        $nan2 = "Infinity" ascii
        $nan3 = "-Infinity" ascii
        $nan4 = "\"confidence\": \"" ascii  // string instead of float
        $overflow = /\"confidence\":\s*[0-9]{4,}/ ascii  // absurdly large number

    condition:
        $conf_field and any of ($nan1, $nan2, $nan3, $nan4, $overflow)
}

rule Neoland_DSPy_ModuleTamper : neoland persistence
{
    meta:
        description = "Detects tampering indicators in DSPy module files (unexpected imports or monkey-patching)"
        author      = "VoidNxLabs SOC"
        date        = "2026-04-07"
        severity    = "high"
        mitre       = "T1546"  // Event Triggered Execution

    strings:
        $dspy_import = "import dspy" ascii
        $patch1 = "monkey" ascii
        $patch2 = "__class__" ascii
        $patch3 = "setattr(" ascii
        $patch4 = "importlib.reload(" ascii
        $patch5 = "ctypes.CDLL(" ascii
        $patch6 = "socket.socket(" ascii
        $patch7 = "requests.post(" ascii  // DSPy modules should not make HTTP calls directly
        $patch8 = "httpx.post(" ascii

    condition:
        $dspy_import and 2 of ($patch*)
}

rule Neoland_RiskLevel_Escalation : neoland manipulation
{
    meta:
        description = "Detects forced risk_level override in pipeline inter-agent messages"
        author      = "VoidNxLabs SOC"
        date        = "2026-04-07"
        severity    = "medium"
        mitre       = "T1565.001"

    strings:
        $risk_field  = "\"risk_level\"" ascii
        $session_id  = "\"session_id\"" ascii
        $override1   = "risk_level\": \"low\"" ascii   // force-downgrade
        $escalate    = "\"escalate_to_architect\": true" ascii
        $abort       = "\"abort_requested\": true" ascii

    condition:
        $risk_field and $session_id and ($override1 and ($escalate or $abort))
}
