import { useState } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { QueryEditor } from './components/QueryEditor'
import { ResultsTable } from './components/ResultsTable'
import { SchemaBrowser } from './components/SchemaBrowser'
import { usePdacQuery } from './hooks/usePdacQuery'
import { usePdacStatus } from './hooks/useSchema'

const queryClient = new QueryClient()

function AppContent() {
  const [sql, setSql] = useState('SELECT TOP 10 * FROM [dbo].[Customers]')
  const [useMockData, setUseMockData] = useState(true)
  const { data, isLoading, error, execute } = usePdacQuery()
  const { data: status, isLoading: statusLoading } = usePdacStatus()

  const handleExecute = async () => {
    await execute({ sql })
  }

  return (
    <div className="flex h-screen bg-slate-50">
      {/* Sidebar - Schema Browser */}
      <div className="w-64 bg-white border-r border-slate-200 overflow-y-auto">
        <div className="p-4">
          <h2 className="text-lg font-semibold text-slate-900">Schema</h2>
          {statusLoading ? (
            <div className="mt-2 text-sm text-slate-500">Checking connection...</div>
          ) : status?.connected ? (
            <div className="mt-2 text-sm text-green-600">✓ Live Database</div>
          ) : (
            <div className="mt-2 text-sm text-amber-600">⚠ Demo Mode (Mock Data)</div>
          )}
        </div>
        <SchemaBrowser useMock={useMockData} onSelectTable={(schema, table) => {
          setSql(`SELECT TOP 100 * FROM [${schema}].[${table}]`)
        }} />
      </div>

      {/* Main Content */}
      <div className="flex-1 flex flex-col">
        {/* Header */}
        <div className="bg-white border-b border-slate-200 px-6 py-4">
          <h1 className="text-2xl font-bold text-slate-900">PDAC Query Tool</h1>
          <p className="text-sm text-slate-600 mt-1">Execute queries and explore the database</p>
        </div>

        {/* Content Area */}
        <div className="flex-1 flex flex-col overflow-hidden">
          {/* Editor */}
          <div className="flex-shrink-0 border-b border-slate-200">
            <QueryEditor
              sql={sql}
              onChange={setSql}
              onExecute={handleExecute}
              isLoading={isLoading}
            />
          </div>

          {/* Results */}
          <div className="flex-1 overflow-hidden">
            {error && (
              <div className="bg-red-50 border-b border-red-200 px-6 py-4">
                <p className="text-red-800 font-semibold">Error</p>
                <p className="text-red-700 text-sm mt-1">{error.message}</p>
              </div>
            )}
            {data && (
              <ResultsTable result={data} />
            )}
            {!data && !error && !isLoading && (
              <div className="flex items-center justify-center h-full">
                <p className="text-slate-500">Execute a query to see results</p>
              </div>
            )}
            {isLoading && (
              <div className="flex items-center justify-center h-full">
                <p className="text-slate-500">Executing query...</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AppContent />
    </QueryClientProvider>
  )
}
