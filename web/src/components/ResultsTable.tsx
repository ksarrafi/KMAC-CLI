import { useMemo } from 'react'
import { FixedSizeList as List } from 'react-window'
import { Copy, Download } from 'lucide-react'
import { QueryResult } from '../types/pdac'

interface ResultsTableProps {
  result: QueryResult
}

export function ResultsTable({ result }: ResultsTableProps) {
  const handleCopyCell = (value: unknown) => {
    const text = value === null ? 'NULL' : String(value)
    navigator.clipboard.writeText(text)
  }

  const handleExportCSV = () => {
    const csv = [
      result.columns.join(','),
      ...result.rows.map(row =>
        row.map(cell =>
          cell === null ? '' : String(cell).includes(',') ? `"${cell}"` : cell
        ).join(',')
      ),
    ].join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'results.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  const columnWidths = useMemo(() => {
    const widths = result.columns.map(() => 150)
    return widths.map((w, i) => Math.max(w, result.columns[i].length * 8))
  }, [result.columns])

  const totalWidth = columnWidths.reduce((a, b) => a + b, 0)

  const Row = ({ index, style }: { index: number; style: React.CSSProperties }) => {
    const row = result.rows[index]
    return (
      <div style={style} className="flex border-b border-slate-200 hover:bg-slate-50">
        {result.columns.map((col, colIndex) => (
          <div
            key={`${index}-${colIndex}`}
            style={{ width: columnWidths[colIndex] }}
            className="px-3 py-2 border-r border-slate-200 text-sm overflow-hidden text-ellipsis whitespace-nowrap flex items-center group"
          >
            <span className="truncate">{row[colIndex] === null ? 'NULL' : String(row[colIndex])}</span>
            <button
              onClick={() => handleCopyCell(row[colIndex])}
              className="ml-1 opacity-0 group-hover:opacity-100 transition-opacity"
              title="Copy cell"
            >
              <Copy size={14} className="text-slate-400 hover:text-slate-600" />
            </button>
          </div>
        ))}
      </div>
    )
  }

  const Header = () => (
    <div className="sticky top-0 flex bg-slate-100 border-b-2 border-slate-300 z-10">
      {result.columns.map((col, i) => (
        <div
          key={col}
          style={{ width: columnWidths[i] }}
          className="px-3 py-2 border-r border-slate-300 text-sm font-semibold text-slate-900 overflow-hidden text-ellipsis whitespace-nowrap"
        >
          {col}
        </div>
      ))}
    </div>
  )

  return (
    <div className="flex flex-col h-full bg-white">
      <div className="flex items-center justify-between px-4 py-3 border-b border-slate-200">
        <div className="text-sm text-slate-600">
          {result.row_count} rows • {result.execution_time_ms}ms
        </div>
        <button
          onClick={handleExportCSV}
          className="flex items-center gap-2 px-3 py-1 text-sm text-slate-700 hover:bg-slate-100 rounded transition-colors"
        >
          <Download size={16} />
          Export CSV
        </button>
      </div>

      <div className="flex-1 overflow-hidden">
        <Header />
        {result.row_count > 0 ? (
          <List
            height={window.innerHeight - 280}
            itemCount={result.row_count}
            itemSize={32}
            width="100%"
          >
            {Row}
          </List>
        ) : (
          <div className="flex items-center justify-center h-32 text-slate-500">
            No rows returned
          </div>
        )}
      </div>
    </div>
  )
}
