"""PDAC schema browser."""

import time
from typing import List, Dict, Any, Optional
from dataclasses import dataclass

try:
    import pyodbc
except ImportError:
    pyodbc = None

from .connection import PDACConnection
from .errors import SchemaError


@dataclass
class Column:
    """Table column metadata."""

    name: str
    type: str
    nullable: bool
    is_identity: bool

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "type": self.type,
            "nullable": self.nullable,
            "is_identity": self.is_identity,
        }


@dataclass
class Table:
    """Table metadata."""

    name: str
    schema: str
    row_count: int
    columns: List[Column]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "schema": self.schema,
            "row_count": self.row_count,
            "columns": [c.to_dict() for c in self.columns],
        }


class SchemaCache:
    """Cache schema metadata with TTL."""

    CACHE_TTL_SECONDS = 3600  # 1 hour

    def __init__(self, connection: PDACConnection):
        self.connection = connection
        self._tables_cache: Optional[List[Table]] = None
        self._cache_time: float = 0

    def _is_cache_valid(self) -> bool:
        """Check if cache is still valid."""
        return (
            self._tables_cache is not None
            and (time.time() - self._cache_time) < self.CACHE_TTL_SECONDS
        )

    def _fetch_tables(self) -> List[Table]:
        """Fetch all tables from schema."""
        try:
            with self.connection.get_connection() as conn:
                cursor = conn.cursor()

                # Get tables with row counts
                cursor.execute(
                    """
                    SELECT
                        t.TABLE_SCHEMA,
                        t.TABLE_NAME,
                        p.rows
                    FROM INFORMATION_SCHEMA.TABLES t
                    LEFT JOIN sys.dm_db_partition_stats p
                        ON object_id('["' + t.TABLE_SCHEMA + '"].["' +
                                     t.TABLE_NAME + '"]') = p.object_id
                        AND p.index_id IN (0, 1)
                    WHERE t.TABLE_TYPE = 'BASE TABLE'
                    ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME
                    """
                )

                tables = []
                for row in cursor.fetchall():
                    schema, name, row_count = row
                    row_count = row_count or 0

                    # Get columns for this table
                    columns = self._fetch_columns(conn, schema, name)
                    tables.append(Table(name, schema, row_count, columns))

                return tables

        except Exception as e:
            raise SchemaError(f"Failed to fetch schema: {e}")

    def _fetch_columns(
        self, conn: Any, schema: str, table_name: str
    ) -> List[Column]:
        """Fetch columns for a specific table."""
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT
                c.COLUMN_NAME,
                c.DATA_TYPE,
                c.IS_NULLABLE,
                CASE WHEN ic.OBJECT_ID IS NOT NULL THEN 1 ELSE 0 END as is_identity
            FROM INFORMATION_SCHEMA.COLUMNS c
            LEFT JOIN sys.identity_columns ic
                ON object_id('[' + c.TABLE_SCHEMA + '].[' +
                             c.TABLE_NAME + ']') = ic.object_id
                AND c.COLUMN_NAME = ic.name
            WHERE c.TABLE_SCHEMA = ? AND c.TABLE_NAME = ?
            ORDER BY c.ORDINAL_POSITION
            """,
            schema,
            table_name,
        )

        columns = []
        for col_name, col_type, nullable, is_identity in cursor.fetchall():
            columns.append(
                Column(
                    name=col_name,
                    type=col_type,
                    nullable=nullable == "YES",
                    is_identity=bool(is_identity),
                )
            )

        return columns

    def get_tables(self, force_refresh: bool = False) -> List[Table]:
        """Get all tables from schema cache."""
        if not force_refresh and self._is_cache_valid():
            return self._tables_cache

        self._tables_cache = self._fetch_tables()
        self._cache_time = time.time()
        return self._tables_cache

    def get_table(
        self, schema: str, name: str, force_refresh: bool = False
    ) -> Optional[Table]:
        """Get specific table by schema and name."""
        tables = self.get_tables(force_refresh=force_refresh)
        for table in tables:
            if table.schema == schema and table.name == name:
                return table
        return None

    def search_tables(self, query: str) -> List[Table]:
        """Search tables by name."""
        tables = self.get_tables()
        query_lower = query.lower()
        return [t for t in tables if query_lower in t.name.lower()]

    def clear_cache(self) -> None:
        """Clear cached schema."""
        self._tables_cache = None
        self._cache_time = 0
