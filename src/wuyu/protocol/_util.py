"""Shared utilities for protocol types."""


def to_camel(snake: str) -> str:
    """Convert snake_case to camelCase for JSON field names."""
    parts = snake.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


CAMEL_CONFIG = {"populate_by_name": True, "alias_generator": to_camel}
