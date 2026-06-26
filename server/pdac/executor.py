"""PDAC query execution engine with safety checks."""

import time
import re
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, asdict

try:
    import pyodbc
except ImportError:
    pyodbc = None

from .connection import PDACConnection
from .errors import QueryExecutionError


@dataclass
class QueryResult:
    """Immutable query result."""

    columns: List[str]
    rows: List[List[Any]]
    row_count: int
    execution_time_ms: float
    error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dict for JSON serialization."""
        return asdict(self)


class PDACExecutor:
    """Execute queries against PDAC database."""

    # Constants
    MAX_ROWS = 100_000
    MAX_EXECUTION_TIME_MS = 30_000
    RESULT_SIZE_LIMIT_MB = 10

    # Regex to detect unsafe operations
    UNSAFE_PATTERNS = [
        r"(?i)drop\s+",
        r"(?i)delete\s+from",
        r"(?i)update\s+",
        r"(?i)insert\s+into",
        r"(?i)truncate\s+",
        r"(?i)alter\s+",
        r"(?i)create\s+",
    ]

    def __init__(self, connection: PDACConnection):
        self.connection = connection

    def _validate_query(self, sql: str) -> None:
        """Validate query safety — read-only only."""
        sql_stripped = sql.strip()

        # Allow EXPLAIN and SELECT only
        if not sql_stripped.upper().startswith(("SELECT", "EXPLAIN", "WITH")):
            raise QueryExecutionError(
                "Only SELECT, EXPLAIN, and WITH queries allowed"
            )

        # Block unsafe patterns
        for pattern in self.UNSAFE_PATTERNS:
            if re.search(pattern, sql):
                raise QueryExecutionError(
                    f"Query contains unsafe operation: {pattern}"
                )

    def execute(
        self,
        sql: str,
        timeout_ms: int = MAX_EXECUTION_TIME_MS,
        max_rows: int = MAX_ROWS,
    ) -> QueryResult:
        """Execute query and return results."""
        self._validate_query(sql)

        start_time = time.time()

        try:
            with self.connection.get_connection() as conn:
                cursor = conn.cursor()

                # Set command timeout (SQL Server specific)
                if pyodbc:
                    cursor.timeout = int(timeout_ms / 1000)

                # Execute query
                cursor.execute(sql)

                # Fetch results
                columns = [desc[0] for desc in cursor.description]
                rows = []

                for row in cursor:
                    if len(rows) >= max_rows:
                        break
                    rows.append(list(row))

                execution_time_ms = (time.time() - start_time) * 1000

                return QueryResult(
                    columns=columns,
                    rows=rows,
                    row_count=len(rows),
                    execution_time_ms=execution_time_ms,
                )

        except QueryExecutionError:
            raise
        except Exception as e:
            execution_time_ms = (time.time() - start_time) * 1000
            error_msg = str(e).split("\n")[0]  # First line only
            return QueryResult(
                columns=[],
                rows=[],
                row_count=0,
                execution_time_ms=execution_time_ms,
                error=error_msg,
            )

    def explain_plan(self, sql: str) -> QueryResult:
        """Get EXPLAIN PLAN for query."""
        self._validate_query(sql)

        explain_sql = f"EXPLAIN\n{sql}"
        return self.execute(explain_sql, timeout_ms=10_000)
