import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Table, SchemaData } from '../types/pdac'

export function useSchema(enabled = true, useMock = false) {
  return useQuery({
    queryKey: ['schema', useMock],
    queryFn: async () => {
      const endpoint = useMock ? '/api/pdac/schema/mock' : '/api/pdac/schema'
      const response = await fetch(endpoint)
      const result = await response.json()
      if (!result.ok) throw new Error(result.error)
      return (result.data as SchemaData).tables
    },
    enabled,
    staleTime: 1000 * 60 * 60,
  })
}

export function useSchemaTables(enabled = true) {
  return useQuery({
    queryKey: ['tables'],
    queryFn: async () => {
      const response = await fetch('/api/pdac/tables')
      const result = await response.json()
      if (!result.ok) throw new Error(result.error)
      return result.data.tables
    },
    enabled,
    staleTime: 1000 * 60 * 60,
  })
}

export function useTableDetail(schema: string, name: string, enabled = true) {
  return useQuery({
    queryKey: ['table', schema, name],
    queryFn: async () => {
      const response = await fetch(`/api/pdac/tables/${schema}/${name}`)
      const result = await response.json()
      if (!result.ok) throw new Error(result.error)
      return result.data.table as Table
    },
    enabled,
    staleTime: 1000 * 60 * 60,
  })
}

export function usePdacStatus() {
  return useQuery({
    queryKey: ['pdac-status'],
    queryFn: async () => {
      const response = await fetch('/api/pdac/status')
      const result = await response.json()
      return result.data
    },
    refetchInterval: 30_000,
  })
}

export function useInvalidateSchema() {
  const queryClient = useQueryClient()
  return () => {
    queryClient.invalidateQueries({ queryKey: ['schema'] })
    queryClient.invalidateQueries({ queryKey: ['tables'] })
  }
}
