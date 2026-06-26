import { useEffect, useRef } from 'react'
import Editor from '@monaco-editor/react'
import { Play, RefreshCw } from 'lucide-react'

interface QueryEditorProps {
  sql: string
  onChange: (sql: string) => void
  onExecute: () => void
  isLoading: boolean
}

export function QueryEditor({ sql, onChange, onExecute, isLoading }: QueryEditorProps) {
  const editorRef = useRef<unknown>(null)

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault()
        onExecute()
      }
    }

    const editorElement = document.querySelector('.monaco-editor')
    editorElement?.addEventListener('keydown', handleKeyDown)
    return () => editorElement?.removeEventListener('keydown', handleKeyDown)
  }, [onExecute])

  return (
    <div className="flex flex-col h-64 bg-white">
      <div className="flex items-center justify-between px-4 py-3 border-b border-slate-200">
        <div className="flex items-center gap-2">
          <h3 className="font-semibold text-slate-900">Query Editor</h3>
          <span className="text-xs text-slate-500">Cmd+Enter to execute</span>
        </div>
        <button
          onClick={onExecute}
          disabled={isLoading}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {isLoading ? (
            <>
              <RefreshCw size={16} className="animate-spin" />
              Executing...
            </>
          ) : (
            <>
              <Play size={16} />
              Execute
            </>
          )}
        </button>
      </div>
      <Editor
        defaultLanguage="sql"
        value={sql}
        onChange={(value) => onChange(value || '')}
        theme="light"
        options={{
          minimap: { enabled: false },
          lineNumbers: 'on',
          wordWrap: 'on',
          fontSize: 12,
          fontFamily: 'monospace',
        }}
        height="100%"
      />
    </div>
  )
}
