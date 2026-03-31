"""Tests for KmacAgent engine components."""

import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from _agent_engine.config import DANGEROUS_PATTERNS
from _agent_engine.memory import MemoryDB
from _agent_engine.tools import _check_dangerous, _trunc, _read_file, _edit_file, _write_file
from _agent_engine.runtime import (
    build_system_prompt, _detect_provider, _estimate_tokens, get_api_key,
)


class TestSafety(unittest.TestCase):
    def test_blocks_rm_rf_root(self):
        self.assertIsNotNone(_check_dangerous("rm -rf /"))

    def test_blocks_rm_rf_home(self):
        self.assertIsNotNone(_check_dangerous("rm -rf ~"))

    def test_blocks_mkfs(self):
        self.assertIsNotNone(_check_dangerous("mkfs.ext4 /dev/sda1"))

    def test_blocks_fork_bomb(self):
        self.assertIsNotNone(_check_dangerous(":(){:|:&};:"))

    def test_blocks_drop_database(self):
        self.assertIsNotNone(_check_dangerous("DROP DATABASE production"))

    def test_allows_normal_commands(self):
        self.assertIsNone(_check_dangerous("ls -la"))
        self.assertIsNone(_check_dangerous("git status"))
        self.assertIsNone(_check_dangerous("python3 script.py"))
        self.assertIsNone(_check_dangerous("rm -rf ./build"))

    def test_allows_safe_rm(self):
        self.assertIsNone(_check_dangerous("rm -rf node_modules"))

    def test_blocks_shutdown(self):
        self.assertIsNotNone(_check_dangerous("shutdown -h now"))


class TestMemoryDB(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.db = MemoryDB(Path(self.tmpdir) / "test.db")

    def tearDown(self):
        self.db.close()
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_create_and_get_agent(self):
        self.db.create_agent("test", model="claude-sonnet-4-6", context="test ctx")
        a = self.db.get_agent("test")
        self.assertEqual(a["name"], "test")
        self.assertEqual(a["context"], "test ctx")

    def test_update_agent(self):
        self.db.create_agent("test")
        self.db.update_agent("test", model="claude-opus-4-6", context="new ctx")
        a = self.db.get_agent("test")
        self.assertEqual(a["model"], "claude-opus-4-6")
        self.assertEqual(a["context"], "new ctx")

    def test_session_crud(self):
        sess = self.db.create_session("default")
        self.assertIsNotNone(sess["id"])
        self.db.update_session(sess["id"], [{"role": "user", "content": "hi"}])
        loaded = self.db.get_session(sess["id"])
        msgs = json.loads(loaded["messages"])
        self.assertEqual(len(msgs), 1)
        self.db.delete_session(sess["id"])
        self.assertIsNone(self.db.get_session(sess["id"]))

    def test_memory_crud(self):
        mid = self.db.add_memory("default", "test fact", "fact", "manual")
        memories = self.db.list_memories("default")
        self.assertEqual(len(memories), 1)
        self.assertEqual(memories[0]["content"], "test fact")
        self.db.delete_memory(mid)
        self.assertEqual(len(self.db.list_memories("default")), 0)

    def test_memory_search(self):
        self.db.add_memory("default", "Python is great for scripting")
        self.db.add_memory("default", "Rust is fast and safe")
        results = self.db.search_memories("default", "Python")
        self.assertTrue(any("Python" in r["content"] for r in results))

    def test_task_lifecycle(self):
        task = self.db.create_task("default", "do something")
        self.assertEqual(task["status"], "queued")
        self.db.update_task(task["id"], "running")
        self.db.update_task(task["id"], "completed", result="done")
        tasks = self.db.list_tasks("default", status="completed")
        self.assertEqual(len(tasks), 1)

    def test_token_logging(self):
        self.db.log_tokens("default", "claude-sonnet-4-6", 1000, 500)
        self.db.log_tokens("default", "claude-sonnet-4-6", 2000, 800)
        usage = self.db.get_token_usage("default")
        self.assertEqual(len(usage), 1)
        self.assertEqual(usage[0]["inp"], 3000)
        self.assertEqual(usage[0]["out"], 1300)

    def test_session_pruning(self):
        import time
        sess = self.db.create_session("default")
        self.db.conn.execute(
            "UPDATE sessions SET updated = '2020-01-01T00:00:00' WHERE id = ?",
            (sess["id"],),
        )
        self.db.conn.commit()
        pruned = self.db.prune_sessions(max_age_days=1)
        self.assertEqual(pruned, 1)

    def test_schedule_crud(self):
        sched = self.db.create_schedule("default", "check disk", "@hourly")
        self.assertEqual(sched["cron"], "@hourly")
        schedules = self.db.list_schedules("default")
        self.assertEqual(len(schedules), 1)
        self.db.delete_schedule(sched["id"])
        self.assertEqual(len(self.db.list_schedules("default")), 0)

    def test_export_import(self):
        self.db.create_agent("test-export")
        self.db.add_memory("test-export", "exported fact")
        data = self.db.export_data()
        self.assertTrue(len(data["agents"]) >= 1)
        self.assertTrue(len(data["memories"]) >= 1)

        db2 = MemoryDB(Path(self.tmpdir) / "test2.db")
        result = db2.import_data(data)
        self.assertTrue(result["agents"] >= 1)
        self.assertTrue(result["memories"] >= 1)
        db2.close()

    def test_stats(self):
        self.db.create_agent("default")
        s = self.db.stats()
        self.assertIn("agents", s)
        self.assertIn("sessions", s)
        self.assertIn("memories", s)
        self.assertIn("total_input_tokens", s)


class TestRuntime(unittest.TestCase):
    def test_detect_provider_anthropic(self):
        self.assertEqual(_detect_provider("claude-sonnet-4-6"), "anthropic")
        self.assertEqual(_detect_provider("claude-opus-4-6"), "anthropic")

    def test_detect_provider_openai(self):
        self.assertEqual(_detect_provider("gpt-4o"), "openai")
        self.assertEqual(_detect_provider("gpt-4o-mini"), "openai")

    def test_detect_provider_ollama(self):
        self.assertEqual(_detect_provider("ollama/llama3.2"), "ollama")

    def test_estimate_tokens(self):
        msgs = [{"content": "hello world"}]
        est = _estimate_tokens(msgs)
        self.assertGreater(est, 0)
        self.assertLess(est, 10)

    def test_build_system_prompt_basic(self):
        prompt = build_system_prompt({"system_prompt": "You are helpful."})
        self.assertIn("You are helpful", prompt)
        self.assertIn("Environment", prompt)

    def test_build_system_prompt_with_memories(self):
        prompt = build_system_prompt(
            {"system_prompt": "Hello"},
            memories=[{"content": "user likes Python"}],
        )
        self.assertIn("user likes Python", prompt)

    def test_build_system_prompt_with_context(self):
        prompt = build_system_prompt(
            {"system_prompt": "Hi", "context": "DevOps specialist"},
        )
        self.assertIn("DevOps specialist", prompt)


class TestTools(unittest.TestCase):
    def test_truncation(self):
        short = "hello"
        self.assertEqual(_trunc(short), short)
        long = "x" * 200000
        truncated = _trunc(long, limit=1000)
        self.assertLess(len(truncated), len(long))
        self.assertIn("truncated", truncated)

    def test_read_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
            f.write("line1\nline2\nline3\n")
            path = f.name
        try:
            result, preview = _read_file({"path": path})
            self.assertIn("line1", result)
            self.assertIn("3 of 3", preview)
        finally:
            os.unlink(path)

    def test_write_file(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            path = f.name
        try:
            result, _ = _write_file({"path": path, "content": "hello\nworld\n"})
            self.assertIn("Wrote", result)
            with open(path) as f:
                self.assertEqual(f.read(), "hello\nworld\n")
        finally:
            os.unlink(path)

    def test_edit_file(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
            f.write("foo bar baz")
            path = f.name
        try:
            result, _ = _edit_file({"path": path, "old_string": "bar", "new_string": "qux"})
            self.assertIn("Edited", result)
            with open(path) as f:
                self.assertEqual(f.read(), "foo qux baz")
        finally:
            os.unlink(path)

    def test_edit_file_not_found(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
            f.write("hello world")
            path = f.name
        try:
            result, _ = _edit_file({"path": path, "old_string": "xyz", "new_string": "abc"})
            self.assertIn("not found", result)
        finally:
            os.unlink(path)


class TestRateLimiter(unittest.TestCase):
    def test_allows_within_limit(self):
        from _agent_engine.rate_limiter import RateLimiter
        rl = RateLimiter(max_rpm=100, max_tpm=1_000_000)
        ok, _ = rl.check(1000)
        self.assertTrue(ok)

    def test_blocks_over_rpm(self):
        from _agent_engine.rate_limiter import RateLimiter
        rl = RateLimiter(max_rpm=2, max_tpm=1_000_000)
        rl.record(100)
        rl.record(100)
        ok, reason = rl.check(100)
        self.assertFalse(ok)
        self.assertIn("requests/min", reason)

    def test_blocks_over_tpm(self):
        from _agent_engine.rate_limiter import RateLimiter
        rl = RateLimiter(max_rpm=100, max_tpm=500)
        rl.record(400)
        ok, reason = rl.check(200)
        self.assertFalse(ok)
        self.assertIn("tokens/min", reason)

    def test_stats(self):
        from _agent_engine.rate_limiter import RateLimiter
        rl = RateLimiter(max_rpm=50, max_tpm=100000)
        rl.record(500)
        s = rl.stats()
        self.assertEqual(s["rpm_current"], 1)
        self.assertEqual(s["tpm_current"], 500)


class TestRAG(unittest.TestCase):
    def test_index_project(self):
        from _agent_engine.rag import index_project
        idx = index_project(".", max_files=20)
        self.assertIsInstance(idx, list)
        if idx:
            self.assertIn("path", idx[0])
            self.assertIn("type", idx[0])

    def test_find_relevant_files(self):
        from _agent_engine.rag import index_project, find_relevant_files
        idx = index_project(".", max_files=50)
        results = find_relevant_files("python test", idx)
        self.assertIsInstance(results, list)

    def test_build_rag_context(self):
        from _agent_engine.rag import build_rag_context
        ctx = build_rag_context("agent daemon", ".", max_chars=2000)
        self.assertIsInstance(ctx, str)


class TestPlugins(unittest.TestCase):
    def test_load_empty(self):
        from _agent_engine.plugins import load_all
        plugins = load_all()
        self.assertIsInstance(plugins, list)

    def test_get_schemas(self):
        from _agent_engine.plugins import get_tool_schemas
        schemas = get_tool_schemas([
            {"name": "test", "description": "test tool",
             "input_schema": {"type": "object"}, "_runner": "/bin/echo", "_plugin": True}
        ])
        self.assertEqual(len(schemas), 1)
        self.assertNotIn("_runner", schemas[0])


class TestCostEstimation(unittest.TestCase):
    def test_estimate_cost_sonnet(self):
        from _agent_engine.runtime import _estimate_cost
        cost = _estimate_cost("claude-sonnet-4-6", 10000)
        self.assertIsNotNone(cost)
        self.assertGreater(cost, 0)

    def test_estimate_cost_unknown(self):
        from _agent_engine.runtime import _estimate_cost
        cost = _estimate_cost("unknown-model", 10000)
        self.assertIsNone(cost)

    def test_estimate_cost_opus_more(self):
        from _agent_engine.runtime import _estimate_cost
        opus = _estimate_cost("claude-opus-4-6", 10000)
        sonnet = _estimate_cost("claude-sonnet-4-6", 10000)
        self.assertGreater(opus, sonnet)


class TestHTMLStripping(unittest.TestCase):
    def test_basic_html(self):
        from _agent_engine.tools_extended import _html_to_text
        html = "<html><body><h1>Title</h1><p>Hello <b>world</b></p></body></html>"
        text = _html_to_text(html)
        self.assertIn("Title", text)
        self.assertIn("Hello", text)
        self.assertIn("world", text)
        self.assertNotIn("<", text)

    def test_strips_script_style(self):
        from _agent_engine.tools_extended import _html_to_text
        html = "<html><head><style>body{}</style></head><body><script>alert(1)</script><p>content</p></body></html>"
        text = _html_to_text(html)
        self.assertIn("content", text)
        self.assertNotIn("alert", text)
        self.assertNotIn("body{}", text)

    def test_empty_html(self):
        from _agent_engine.tools_extended import _html_to_text
        self.assertEqual(_html_to_text(""), "")


class TestApplyPatch(unittest.TestCase):
    def test_simple_patch(self):
        from _agent_engine.tools_extended import _apply_patch
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
            f.write("line1\nline2\nline3\n")
            path = f.name
        try:
            base_dir = os.path.dirname(path)
            fname = os.path.basename(path)
            patch = f"""--- a/{fname}
+++ b/{fname}
@@ -1,3 +1,3 @@
 line1
-line2
+line2_modified
 line3
"""
            result, _ = _apply_patch({"patch": patch, "base_dir": base_dir})
            self.assertIn("1 file", result)
            self.assertIn("1 hunk", result)
            with open(path) as f:
                content = f.read()
            self.assertIn("line2_modified", content)
            self.assertNotIn("line2\n", content)
        finally:
            os.unlink(path)

    def test_new_file_patch(self):
        from _agent_engine.tools_extended import _apply_patch
        tmpdir = tempfile.mkdtemp()
        try:
            patch = """--- /dev/null
+++ b/newfile.txt
@@ -0,0 +1,2 @@
+hello
+world
"""
            result, _ = _apply_patch({"patch": patch, "base_dir": tmpdir})
            self.assertIn("1 file", result)
            newpath = os.path.join(tmpdir, "newfile.txt")
            self.assertTrue(os.path.exists(newpath))
            with open(newpath) as f:
                content = f.read()
            self.assertIn("hello", content)
        finally:
            import shutil
            shutil.rmtree(tmpdir)

    def test_invalid_patch(self):
        from _agent_engine.tools_extended import _apply_patch
        result, _ = _apply_patch({"patch": "not a valid diff"})
        self.assertIn("No files patched", result)


class TestToolProfiles(unittest.TestCase):
    def test_full_profile_allows_all(self):
        from _agent_engine.tool_profiles import filter_tools
        all_tools = [{"name": "bash"}, {"name": "web_search"}, {"name": "image"}]
        config = {"config": json.dumps({"tools": {"profile": "full"}})}
        filtered = filter_tools(all_tools, config)
        self.assertEqual(len(filtered), 3)

    def test_safe_profile_blocks_bash(self):
        from _agent_engine.tool_profiles import filter_tools
        all_tools = [{"name": "bash"}, {"name": "read_file"}, {"name": "web_search"}]
        config = {"config": json.dumps({"tools": {"profile": "safe"}})}
        filtered = filter_tools(all_tools, config)
        names = {t["name"] for t in filtered}
        self.assertNotIn("bash", names)
        self.assertIn("read_file", names)
        self.assertIn("web_search", names)

    def test_deny_overrides_allow(self):
        from _agent_engine.tool_profiles import filter_tools
        all_tools = [{"name": "bash"}, {"name": "web_search"}, {"name": "read_file"}]
        config = {"config": json.dumps({"tools": {"profile": "full", "deny": ["bash"]}})}
        filtered = filter_tools(all_tools, config)
        names = {t["name"] for t in filtered}
        self.assertNotIn("bash", names)
        self.assertIn("web_search", names)

    def test_minimal_with_allow(self):
        from _agent_engine.tool_profiles import filter_tools
        all_tools = [{"name": "bash"}, {"name": "web_search"}, {"name": "read_file"}]
        config = {"config": json.dumps({"tools": {"profile": "minimal", "allow": ["web_search"]}})}
        filtered = filter_tools(all_tools, config)
        self.assertEqual(len(filtered), 1)
        self.assertEqual(filtered[0]["name"], "web_search")

    def test_group_expansion(self):
        from _agent_engine.tool_profiles import _expand_groups
        result = _expand_groups(["group:web"])
        self.assertIn("web_search", result)
        self.assertIn("web_fetch", result)

    def test_no_config_returns_all(self):
        from _agent_engine.tool_profiles import filter_tools
        all_tools = [{"name": "bash"}, {"name": "read_file"}]
        config = {}
        filtered = filter_tools(all_tools, config)
        self.assertEqual(len(filtered), 2)

    def test_profile_names(self):
        from _agent_engine.tool_profiles import get_profile_names
        names = get_profile_names()
        self.assertIn("full", names)
        self.assertIn("safe", names)
        self.assertIn("coding", names)
        self.assertIn("minimal", names)


class TestSkills(unittest.TestCase):
    def test_find_no_skills(self):
        from _agent_engine.skills import find_skill_files
        files = find_skill_files("nonexistent-agent", "/tmp/nonexistent")
        self.assertIsInstance(files, list)

    def test_load_skill_file(self):
        from _agent_engine.skills import load_skills
        tmpdir = tempfile.mkdtemp()
        skill_dir = os.path.join(tmpdir, ".kmac", "skills", "testing")
        os.makedirs(skill_dir)
        skill_path = os.path.join(skill_dir, "SKILL.md")
        with open(skill_path, "w") as f:
            f.write("# Testing Skill\nAlways write unit tests for new code.\n")
        try:
            skills = load_skills("default", tmpdir)
            self.assertEqual(len(skills), 1)
            self.assertEqual(skills[0]["name"], "testing")
            self.assertIn("unit tests", skills[0]["content"])
        finally:
            import shutil
            shutil.rmtree(tmpdir)

    def test_build_skills_prompt(self):
        from _agent_engine.skills import build_skills_prompt
        tmpdir = tempfile.mkdtemp()
        skill_dir = os.path.join(tmpdir, ".kmac", "skills", "lint")
        os.makedirs(skill_dir)
        with open(os.path.join(skill_dir, "SKILL.md"), "w") as f:
            f.write("# Lint Skill\nAlways run linter before commit.\n")
        try:
            prompt = build_skills_prompt("default", tmpdir)
            self.assertIn("Skills (1 loaded)", prompt)
            self.assertIn("Lint Skill", prompt)
        finally:
            import shutil
            shutil.rmtree(tmpdir)

    def test_empty_skill_file_ignored(self):
        from _agent_engine.skills import load_skills
        tmpdir = tempfile.mkdtemp()
        skill_dir = os.path.join(tmpdir, ".kmac", "skills", "empty")
        os.makedirs(skill_dir)
        with open(os.path.join(skill_dir, "SKILL.md"), "w") as f:
            f.write("")
        try:
            skills = load_skills("default", tmpdir)
            self.assertEqual(len(skills), 0)
        finally:
            import shutil
            shutil.rmtree(tmpdir)


class TestWorkflows(unittest.TestCase):
    def test_list_builtin_workflows(self):
        from _agent_engine.workflows import list_workflows
        wfs = list_workflows()
        self.assertIsInstance(wfs, list)
        self.assertGreater(len(wfs), 0)
        names = {w["id"] for w in wfs}
        self.assertIn("lint-fix", names)
        self.assertIn("security-scan", names)
        self.assertIn("deploy-check", names)

    def test_load_workflow(self):
        from _agent_engine.workflows import load_workflow
        wf = load_workflow("lint-fix")
        self.assertIsNotNone(wf)
        self.assertEqual(wf["name"], "Lint & Fix")
        self.assertIn("steps", wf)
        self.assertGreater(len(wf["steps"]), 0)

    def test_load_nonexistent(self):
        from _agent_engine.workflows import load_workflow
        wf = load_workflow("does-not-exist-xyz")
        self.assertIsNone(wf)

    def test_interpolation(self):
        from _agent_engine.workflows import _interpolate
        ctx = {"variables": {"name": "world"}, "results": {"step1": "ok"}}
        self.assertEqual(_interpolate("hello {{name}}", ctx), "hello world")
        self.assertEqual(_interpolate("result: {{step1}}", ctx), "result: ok")
        self.assertEqual(_interpolate("no {{match}}", ctx), "no {{match}}")

    def test_set_step(self):
        from _agent_engine.workflows import _run_set_step
        ctx = {"variables": {}, "results": {}}
        step = {"variables": {"foo": "bar", "count": "42"}}
        result = _run_set_step(step, ctx)
        self.assertEqual(ctx["variables"]["foo"], "bar")
        self.assertIn("2 variables", result)

    def test_check_step_contains(self):
        from _agent_engine.workflows import _run_check_step
        ctx = {"variables": {"output": "found 3 errors"}, "results": {}}
        steps = [{"id": "a"}, {"id": "b"}, {"id": "c"}]
        step = {
            "variable": "output", "operator": "contains", "value": "errors",
            "then_goto": "c", "else_goto": "a",
        }
        result, jump = _run_check_step(step, ctx, steps)
        self.assertIn("True", result)
        self.assertEqual(jump, 2)

    def test_check_step_empty(self):
        from _agent_engine.workflows import _run_check_step
        ctx = {"variables": {"output": ""}, "results": {}}
        steps = [{"id": "a"}]
        step = {"variable": "output", "operator": "empty", "value": ""}
        result, jump = _run_check_step(step, ctx, steps)
        self.assertIn("True", result)

    def test_execute_simple_workflow(self):
        import asyncio
        from _agent_engine.workflows import execute_workflow
        tmpdir = tempfile.mkdtemp()
        wf_path = os.path.join(tmpdir, "test-wf.json")
        with open(wf_path, "w") as f:
            json.dump({
                "name": "Test",
                "steps": [
                    {"id": "s1", "type": "set", "variables": {"greeting": "hello"}},
                    {"id": "s2", "type": "log", "message": "{{greeting}} world"},
                ]
            }, f)
        try:
            from _agent_engine.workflows import BUILTIN_DIR
            orig = BUILTIN_DIR
            import _agent_engine.workflows as wm
            wm.BUILTIN_DIR = Path(tmpdir)
            result = asyncio.run(execute_workflow("test-wf", workspace=tmpdir))
            wm.BUILTIN_DIR = orig
            self.assertEqual(result["status"], "completed")
            self.assertIn("[s2] hello world", result["log"])
        finally:
            import shutil
            shutil.rmtree(tmpdir)


class TestExtendedTools(unittest.TestCase):
    def test_tool_schemas_present(self):
        from _agent_engine.tools_extended import EXTENDED_TOOLS
        names = {t["name"] for t in EXTENDED_TOOLS}
        self.assertIn("web_search", names)
        self.assertIn("web_fetch", names)
        self.assertIn("browser", names)
        self.assertIn("image", names)
        self.assertIn("image_generate", names)
        self.assertIn("apply_patch", names)
        self.assertEqual(len(EXTENDED_TOOLS), 6)

    def test_each_has_required_fields(self):
        from _agent_engine.tools_extended import EXTENDED_TOOLS
        for tool in EXTENDED_TOOLS:
            self.assertIn("name", tool)
            self.assertIn("description", tool)
            self.assertIn("input_schema", tool)
            self.assertIn("required", tool["input_schema"])


class TestSessionFork(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        from _agent_engine.memory import MemoryDB
        self.db = MemoryDB(Path(self.tmpdir) / "test.db")

    def tearDown(self):
        self.db.close()
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_fork_session(self):
        sess = self.db.create_session("default")
        msgs = [{"role": "user", "content": "hello"}, {"role": "assistant", "content": "hi"}]
        self.db.update_session(sess["id"], msgs)

        new_sess = self.db.create_session("default")
        original = self.db.get_session(sess["id"])
        self.db.update_session(new_sess["id"], json.loads(original["messages"]))

        forked = self.db.get_session(new_sess["id"])
        forked_msgs = json.loads(forked["messages"])
        self.assertEqual(len(forked_msgs), 2)
        self.assertEqual(forked_msgs[0]["content"], "hello")


if __name__ == "__main__":
    unittest.main()
