"""Tests for ThreadItem parsing."""

from wuyu.protocol.items import (
    AgentMessageItem,
    CommandExecutionItem,
    FileChangeItem,
    McpToolCallItem,
    ReasoningItem,
    UnknownItem,
    UserMessageItem,
    WebSearchItem,
    parse_thread_item,
)


class TestParseThreadItem:
    def test_user_message(self):
        item = parse_thread_item({"type": "userMessage", "id": "u1", "text": "hello"})
        assert isinstance(item, UserMessageItem)
        assert item.text == "hello"
        assert item.id == "u1"

    def test_agent_message(self):
        item = parse_thread_item(
            {
                "type": "agentMessage",
                "id": "a1",
                "text": "I'll help",
                "phase": "responding",
            }
        )
        assert isinstance(item, AgentMessageItem)
        assert item.text == "I'll help"
        assert item.phase == "responding"

    def test_command_execution(self):
        item = parse_thread_item(
            {
                "type": "commandExecution",
                "id": "c1",
                "command": "ls -la",
                "cwd": "/home/user",
                "status": "completed",
                "exit_code": 0,
                "stdout": "file1\nfile2",
                "stderr": "",
            }
        )
        assert isinstance(item, CommandExecutionItem)
        assert item.command == "ls -la"
        assert item.exit_code == 0

    def test_file_change(self):
        item = parse_thread_item(
            {
                "type": "fileChange",
                "id": "f1",
                "file_path": "src/main.py",
                "status": "applied",
                "patch": "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new",
            }
        )
        assert isinstance(item, FileChangeItem)
        assert item.file_path == "src/main.py"

    def test_reasoning(self):
        item = parse_thread_item({"type": "reasoning", "id": "r1", "text": "thinking..."})
        assert isinstance(item, ReasoningItem)
        assert item.text == "thinking..."

    def test_web_search(self):
        item = parse_thread_item({"type": "webSearch", "id": "w1", "query": "python pydantic"})
        assert isinstance(item, WebSearchItem)
        assert item.query == "python pydantic"

    def test_mcp_tool_call(self):
        item = parse_thread_item(
            {
                "type": "mcpToolCall",
                "id": "m1",
                "tool_name": "read_file",
                "server_name": "filesystem",
                "arguments": {"path": "/tmp/test.py"},
                "result": "file contents",
            }
        )
        assert isinstance(item, McpToolCallItem)
        assert item.tool_name == "read_file"

    def test_unknown_type_fallback(self):
        item = parse_thread_item(
            {
                "type": "futureNewType",
                "id": "x1",
                "someField": "someValue",
            }
        )
        assert isinstance(item, UnknownItem)
        assert item.type == "futureNewType"
        assert item.id == "x1"
        assert item.raw["someField"] == "someValue"

    def test_missing_type_fallback(self):
        item = parse_thread_item({"id": "y1"})
        assert isinstance(item, UnknownItem)
        assert item.type == ""

    def test_minimal_agent_message(self):
        """Agent message with only required fields."""
        item = parse_thread_item({"type": "agentMessage", "id": "a2"})
        assert isinstance(item, AgentMessageItem)
        assert item.text == ""
        assert item.phase is None
