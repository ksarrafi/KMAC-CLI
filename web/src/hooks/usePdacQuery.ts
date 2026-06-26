import { useState, useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'
import { QueryResult } from '../types/pdac'

interface ExecuteOptions {
  sql: string
  timeout_ms?: number
}

interface UsePdacQueryResult {
  data: QueryResult | null
  isLoading: boolean
  error: Error | null
  execute: (options: ExecuteOptions) => Promise<void>
}

export function usePdacQuery(): UsePdacQueryResult {
  const [queryData, setQueryData] = useState<QueryResult | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<Error | null>(null)

  const execute = useCallback(async (options: ExecuteOptions) => {
    setIsLoading(true)
    setError(null)

    try {
      const response = await fetch('/api/pdac/query', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sql: options.sql,
          timeout_ms: options.timeout_ms || 30_000,
        }),
      })

      if (!response.ok) {
        throw new Error(`Request failed: ${response.statusText}`)
      }

      const result = await response.json()
      if (!result.ok) {
        throw new Error(result.error || 'Query execution failed')
      }

      setQueryData(result.data)
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)))
    } finally {
      setIsLoading(false)
    }
  }, [])

  return { data: queryData, isLoading, error, execute }
}

export function usePdacExplainPlan(sql: string) {
  return useQuery({
    queryKey: ['explain', sql],
    queryFn: async () => {
      const response = await fetch('/api/pdac/explain', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sql }),
      })
      const result = await response.json()
      if (!result.ok) throw new Error(result.error)
      return result.data as QueryResult
    },
    enabled: false,
  })
}
