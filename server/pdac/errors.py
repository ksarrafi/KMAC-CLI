"""PDAC error types."""


class PDACError(Exception):
    """Base PDAC error."""

    pass


class QueryExecutionError(PDACError):
    """Query execution failed."""

    def __init__(self, message: str, original_error: Exception = None):
        super().__init__(message)
        self.original_error = original_error


class SchemaError(PDACError):
    """Schema retrieval failed."""

    pass


class ConnectionError(PDACError):
    """Database connection failed."""

    pass
