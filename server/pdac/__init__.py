"""PDAC database module — query execution, schema browsing, EXPLAIN plans."""

from .connection import PDACConnection, get_pdac_connection
from .executor import PDACExecutor, QueryResult
from .schema import SchemaCache
from .errors import PDACError, QueryExecutionError, SchemaError

__all__ = [
    "PDACConnection",
    "get_pdac_connection",
    "PDACExecutor",
    "QueryResult",
    "SchemaCache",
    "PDACError",
    "QueryExecutionError",
    "SchemaError",
]
