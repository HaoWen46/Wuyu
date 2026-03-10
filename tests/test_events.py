"""Tests for event notification parsing."""

from wuyu.protocol.events import (
    AgentMessageDeltaNotification,
    ItemCompletedNotification,
    ItemStartedNotification,
    TurnCompletedNotification,
    TurnStartedNotification,
    parse_notification_params,
)
from wuyu.protocol.items import AgentMessageItem, UserMessageItem
from wuyu.protocol.types import TurnStatus


class TestNotificationParsing:
    def test_turn_started(self):
        params = {
            "threadId": "t1",
            "turn": {
                "id": "turn-1",
                "items": [],
                "status": "inProgress",
                "error": None,
            },
        }
        notif = parse_notification_params("turn/started", params)
        assert isinstance(notif, TurnStartedNotification)
        assert notif.thread_id == "t1"
        assert notif.turn.status == TurnStatus.IN_PROGRESS

    def test_turn_completed(self):
        params = {
            "threadId": "t1",
            "turn": {
                "id": "turn-1",
                "items": [],
                "status": "completed",
                "error": None,
            },
        }
        notif = parse_notification_params("turn/completed", params)
        assert isinstance(notif, TurnCompletedNotification)
        assert notif.turn.status == TurnStatus.COMPLETED

    def test_item_started(self):
        params = {
            "item": {"type": "agentMessage", "id": "a1", "text": ""},
            "threadId": "t1",
            "turnId": "turn-1",
        }
        notif = parse_notification_params("item/started", params)
        assert isinstance(notif, ItemStartedNotification)
        assert notif.thread_id == "t1"
        # Can parse the item into a typed object
        item = notif.parse_item()
        assert isinstance(item, AgentMessageItem)

    def test_item_completed(self):
        params = {
            "item": {"type": "userMessage", "id": "u1", "text": "hello"},
            "threadId": "t1",
            "turnId": "turn-1",
        }
        notif = parse_notification_params("item/completed", params)
        assert isinstance(notif, ItemCompletedNotification)
        item = notif.parse_item()
        assert isinstance(item, UserMessageItem)
        assert item.text == "hello"

    def test_agent_message_delta(self):
        params = {
            "threadId": "t1",
            "turnId": "turn-1",
            "itemId": "a1",
            "delta": "Hello, ",
        }
        notif = parse_notification_params("item/agentMessage/delta", params)
        assert isinstance(notif, AgentMessageDeltaNotification)
        assert notif.delta == "Hello, "
        assert notif.item_id == "a1"

    def test_unknown_method_returns_none(self):
        result = parse_notification_params("some/future/method", {"foo": "bar"})
        assert result is None

    def test_none_params_returns_none(self):
        result = parse_notification_params("turn/started", None)
        assert result is None
