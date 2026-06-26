export interface Column {
  name: string
  type: string
  nullable: boolean
  is_identity: boolean
}

export interface Table {
  name: string
  schema: string
  row_count: number
  columns: Column[]
}

export interface QueryResult {
  columns: string[]
  rows: (string | number | null)[][]
  row_count: number
  execution_time_ms: number
  error: string | null
}

export interface ApiResponse<T> {
  ok: boolean
  data?: T
  error?: string
}

export interface SchemaData {
  tables: Table[]
}

export interface QueryData {
  columns: string[]
  rows: any[][]
  row_count: number
  execution_time_ms: number
  error: string | null
}

export interface TableListData {
  tables: Omit<Table, 'columns'>[]
}

export interface TableDetailData {
  table: Table
}

export interface SampleDataData {
  columns: string[]
  rows: (string | number | boolean | null)[][]
  row_count: number
  execution_time_ms: number
  error: string | null
}

export interface StatusData {
  connected: boolean
}
