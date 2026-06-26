import { useState } from 'react'
import { ChevronRight, ChevronDown, Database } from 'lucide-react'
import { useSchema } from '../hooks/useSchema'
import { Table } from '../types/pdac'

interface SchemaBrowserProps {
  onSelectTable: (schema: string, table: string) => void
  useMock?: boolean
}

export function SchemaBrowser({ onSelectTable, useMock = true }: SchemaBrowserProps) {
  const { data: tables, isLoading, error } = useSchema(true, useMock)
  const [expandedSchemas, setExpandedSchemas] = useState<Set<string>>(new Set())
  const [searchQuery, setSearchQuery] = useState('')

  const toggleSchema = (schema: string) => {
    const newExpanded = new Set(expandedSchemas)
    if (newExpanded.has(schema)) {
      newExpanded.delete(schema)
    } else {
      newExpanded.add(schema)
    }
    setExpandedSchemas(newExpanded)
  }

  const groupedTables = tables?.reduce(
    (acc, table) => {
      if (!acc[table.schema]) acc[table.schema] = []
      acc[table.schema].push(table)
      return acc
    },
    {} as Record<string, Table[]>
  ) || {}

  const filteredSchemas = Object.entries(groupedTables)
    .filter(([, tables]) =>
      tables.some(t =>
        t.name.toLowerCase().includes(searchQuery.toLowerCase())
      )
    )
    .sort(([a], [b]) => a.localeCompare(b))

  return (
    <div className="flex flex-col h-full">
      <div className="px-4 py-2">
        <input
          type="text"
          placeholder="Search tables..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="w-full px-2 py-1 text-sm border border-slate-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>

      <div className="flex-1 overflow-y-auto">
        {isLoading && (
          <div className="px-4 py-2 text-sm text-slate-500">Loading...</div>
        )}
        {error && (
          <div className="px-4 py-2 text-sm text-red-600">Failed to load schema</div>
        )}
        {filteredSchemas.map(([schema, schemaTables]) => (
          <div key={schema}>
            <button
              onClick={() => toggleSchema(schema)}
              className="w-full flex items-center gap-2 px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-100 transition-colors"
            >
              {expandedSchemas.has(schema) ? (
                <ChevronDown size={16} />
              ) : (
                <ChevronRight size={16} />
              )}
              <Database size={14} />
              {schema}
            </button>

            {expandedSchemas.has(schema) && (
              <div className="bg-slate-50">
                {schemaTables.map((table) => (
                  <button
                    key={`${schema}.${table.name}`}
                    onClick={() => onSelectTable(schema, table.name)}
                    className="w-full text-left px-8 py-1 text-sm text-slate-600 hover:bg-blue-100 hover:text-blue-900 transition-colors"
                    title={`${table.row_count} rows`}
                  >
                    <span className="truncate block">{table.name}</span>
                    <span className="text-xs text-slate-400">
                      {table.row_count.toLocaleString()} rows
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
