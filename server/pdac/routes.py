"""PDAC API endpoints for aiohttp."""

import json
from aiohttp import web

from .connection import get_pdac_connection
from .executor import PDACExecutor
from .schema import SchemaCache
from .errors import PDACError, ConnectionError


async def handle_pdac_query(request: web.Request) -> web.Response:
    """Execute SQL query. POST /api/pdac/query"""
    try:
        data = await request.json()
        sql = data.get("sql", "").strip()
        timeout_ms = data.get("timeout_ms", 30_000)

        if not sql:
            return web.json_response(
                {"ok": False, "error": "sql required"}, status=400
            )

        conn = get_pdac_connection()
        executor = PDACExecutor(conn)
        result = executor.execute(sql, timeout_ms=timeout_ms)

        return web.json_response(
            {
                "ok": result.error is None,
                "data": result.to_dict(),
            }
        )

    except PDACError as e:
        return web.json_response(
            {"ok": False, "error": str(e)}, status=400
        )
    except Exception as e:
        return web.json_response(
            {"ok": False, "error": f"Server error: {str(e)}"}, status=500
        )


async def handle_pdac_explain(request: web.Request) -> web.Response:
    """Get EXPLAIN PLAN for query. POST /api/pdac/explain"""
    try:
        data = await request.json()
        sql = data.get("sql", "").strip()

        if not sql:
            return web.json_response(
                {"ok": False, "error": "sql required"}, status=400
            )

        conn = get_pdac_connection()
        executor = PDACExecutor(conn)
        result = executor.explain_plan(sql)

        return web.json_response(
            {
                "ok": result.error is None,
                "data": result.to_dict(),
            }
        )

    except PDACError as e:
        return web.json_response(
            {"ok": False, "error": str(e)}, status=400
        )
    except Exception as e:
        return web.json_response(
            {"ok": False, "error": f"Server error: {str(e)}"}, status=500
        )


async def handle_pdac_schema(request: web.Request) -> web.Response:
    """Get full schema. GET /api/pdac/schema"""
    try:
        force_refresh = request.query.get("refresh") == "true"

        conn = get_pdac_connection()
        cache = SchemaCache(conn)
        tables = cache.get_tables(force_refresh=force_refresh)

        return web.json_response(
            {
                "ok": True,
                "data": {"tables": [t.to_dict() for t in tables]},
            }
        )

    except PDACError as e:
        return web.json_response(
            {"ok": False, "error": str(e)}, status=400
        )
    except Exception as e:
        return web.json_response(
            {"ok": False, "error": f"Server error: {str(e)}"}, status=500
        )


async def handle_pdac_tables(request: web.Request) -> web.Response:
    """List all tables. GET /api/pdac/tables"""
    try:
        conn = get_pdac_connection()
        cache = SchemaCache(conn)
        tables = cache.get_tables()

        # Return lightweight table list (no columns)
        table_list = [
            {
                "name": t.name,
                "schema": t.schema,
                "row_count": t.row_count,
            }
            for t in tables
        ]

        return web.json_response(
            {
                "ok": True,
                "data": {"tables": table_list},
            }
        )

    except PDACError as e:
        return web.json_response(
            {"ok": False, "error": str(e)}, status=400
        )
    except Exception as e:
        return web.json_response(
            {"ok": False, "error": f"Server error: {str(e)}"}, status=500
        )


async def handle_pdac_table_detail(request: web.Request) -> web.Response:
    """Get table details. GET /api/pdac/tables/{schema}/{name}"""
    try:
        schema = request.match_info.get("schema")
        name = request.match_info.get("name")

        if not schema or not name:
            return web.json_response(
                {"ok": False, "error": "schema and name required"},
                status=400,
            )

        conn = get_pdac_connection()
        cache = SchemaCache(conn)
        table = cache.get_table(schema, name)

        if not table:
            return web.json_response(
                {"ok": False, "error": "table not found"}, status=404
            )

        return web.json_response(
            {
                "ok": True,
                "data": {"table": table.to_dict()},
            }
        )

    except PDACError as e:
        return web.json_response(
            {"ok": False, "error": str(e)}, status=400
        )
    except Exception as e:
        return web.json_response(
            {"ok": False, "error": f"Server error: {str(e)}"}, status=500
        )


async def handle_pdac_sample_data(request: web.Request) -> web.Response:
    """Get sample data from table. POST /api/pdac/sample"""
    try:
        data = await request.json()
        schema = data.get("schema")
        table_name = data.get("table")
        limit = min(int(data.get("limit", 100)), 1000)

        if not schema or not table_name:
            return web.json_response(
                {"ok": False, "error": "schema and table required"},
                status=400,
            )

        # Build safe query
        sql = (
            f'SELECT TOP {limit} * FROM [{schema}].[{table_name}]'
        )

        conn = get_pdac_connection()
        executor = PDACExecutor(conn)
        result = executor.execute(sql, timeout_ms=10_000, max_rows=limit)

        return web.json_response(
            {
                "ok": result.error is None,
                "data": result.to_dict(),
            }
        )

    except PDACError as e:
        return web.json_response(
            {"ok": False, "error": str(e)}, status=400
        )
    except Exception as e:
        return web.json_response(
            {"ok": False, "error": f"Server error: {str(e)}"}, status=500
        )


async def handle_pdac_status(request: web.Request) -> web.Response:
    """Check PDAC connection status. GET /api/pdac/status"""
    try:
        conn = get_pdac_connection()

        # Try to verify connection
        try:
            with conn.get_connection() as db_conn:
                cursor = db_conn.cursor()
                cursor.execute("SELECT 1")
                connected = True
        except Exception:
            connected = False

        return web.json_response(
            {
                "ok": True,
                "data": {"connected": connected},
            }
        )

    except Exception as e:
        return web.json_response(
            {
                "ok": False,
                "data": {"connected": False},
                "error": str(e),
            },
            status=500,
        )


async def handle_pdac_schema_mock(request: web.Request) -> web.Response:
    """Mock schema for testing (when DB unavailable)."""
    return web.json_response(
        {
            "ok": True,
            "data": {
                "tables": [
                    {
                        "name": "Customers",
                        "schema": "dbo",
                        "row_count": 1250,
                        "columns": [
                            {
                                "name": "CustomerID",
                                "type": "int",
                                "nullable": False,
                                "is_identity": True,
                            },
                            {
                                "name": "Name",
                                "type": "nvarchar(255)",
                                "nullable": False,
                                "is_identity": False,
                            },
                        ],
                    },
                    {
                        "name": "Orders",
                        "schema": "dbo",
                        "row_count": 5430,
                        "columns": [
                            {
                                "name": "OrderID",
                                "type": "int",
                                "nullable": False,
                                "is_identity": True,
                            },
                            {
                                "name": "CustomerID",
                                "type": "int",
                                "nullable": False,
                                "is_identity": False,
                            },
                        ],
                    },
                ]
            },
        }
    )


def register_pdac_routes(app: web.Application) -> None:
    """Register all PDAC routes."""
    app.router.add_post("/api/pdac/query", handle_pdac_query)
    app.router.add_post("/api/pdac/explain", handle_pdac_explain)
    app.router.add_get("/api/pdac/schema", handle_pdac_schema)
    app.router.add_get("/api/pdac/schema/mock", handle_pdac_schema_mock)
    app.router.add_get("/api/pdac/tables", handle_pdac_tables)
    app.router.add_get(
        "/api/pdac/tables/{schema}/{name}", handle_pdac_table_detail
    )
    app.router.add_post("/api/pdac/sample", handle_pdac_sample_data)
    app.router.add_get("/api/pdac/status", handle_pdac_status)
