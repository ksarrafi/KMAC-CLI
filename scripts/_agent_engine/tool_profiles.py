"""Tool profiles — allow/deny lists and tool groups for restricting agent capabilities.

Profiles set a base allowlist, then allow/deny refine it. Deny always wins.

Configuration in agent config JSON:
{
    "tools": {
        "profile": "coding",       // base profile
        "allow": ["web_search"],    // additionally allow
        "deny": ["bash"]           // deny even if profile allows
    }
}
"""

import json
import logging

log = logging.getLogger("kmac-agent")

# ── Tool Groups ──────────────────────────────────────────────────

TOOL_GROUPS = {
    "group:runtime": {"bash"},
    "group:fs": {"read_file", "write_file", "edit_file", "apply_patch", "list_dir", "grep_search"},
    "group:sessions": {"delegate_agent"},
    "group:web": {"web_search", "web_fetch"},
    "group:browser": {"browser"},
    "group:image": {"image", "image_generate"},
    "group:automation": set(),
    "group:all": None,
}

# ── Profiles ─────────────────────────────────────────────────────

PROFILES = {
    "full": None,  # None = all tools allowed
    "coding": {
        "bash", "read_file", "write_file", "edit_file", "apply_patch",
        "list_dir", "grep_search", "web_search", "web_fetch",
        "delegate_agent", "image",
    },
    "web": {
        "web_search", "web_fetch", "browser", "image", "image_generate",
        "read_file", "write_file",
    },
    "messaging": {
        "delegate_agent", "web_search", "web_fetch",
    },
    "minimal": set(),
    "safe": {
        "read_file", "list_dir", "grep_search",
        "web_search", "web_fetch", "image",
    },
}


def _expand_groups(names: list[str]) -> set[str]:
    """Expand group:* shorthands into individual tool names."""
    result = set()
    for name in names:
        if name in TOOL_GROUPS:
            group = TOOL_GROUPS[name]
            if group is None:
                return None  # "all" means no restrictions
            result.update(group)
        else:
            result.add(name)
    return result


def filter_tools(all_tools: list[dict], agent_config: dict) -> list[dict]:
    """Filter tool list based on agent's tool profile configuration.

    Returns a filtered list of tool schemas.
    """
    config = agent_config.get("config", "{}")
    if isinstance(config, str):
        try:
            config = json.loads(config)
        except (json.JSONDecodeError, TypeError):
            config = {}

    tools_cfg = config.get("tools", {})
    if not tools_cfg:
        return all_tools

    profile_name = tools_cfg.get("profile", "full")
    allow_list = tools_cfg.get("allow", [])
    deny_list = tools_cfg.get("deny", [])

    # Start with profile base set
    profile = PROFILES.get(profile_name, None)

    if profile is None:
        allowed = None  # all tools
    else:
        allowed = set(profile)

    # Expand and add allows
    if allow_list:
        extra = _expand_groups(allow_list)
        if extra is None:
            allowed = None
        elif allowed is not None:
            allowed.update(extra)

    # Expand denies
    denied = set()
    if deny_list:
        expanded = _expand_groups(deny_list)
        if expanded is not None:
            denied = expanded

    # Apply filter
    filtered = []
    for tool in all_tools:
        name = tool["name"]
        if allowed is not None and name not in allowed:
            continue
        if name in denied:
            continue
        filtered.append(tool)

    if len(filtered) != len(all_tools):
        log.info("Tool profile '%s': %d/%d tools enabled",
                 profile_name, len(filtered), len(all_tools))

    return filtered


def get_profile_names() -> list[str]:
    return list(PROFILES.keys())


def get_group_names() -> list[str]:
    return list(TOOL_GROUPS.keys())
