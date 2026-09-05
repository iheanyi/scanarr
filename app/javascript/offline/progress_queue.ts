interface ProgressQueueEntry {
  progressUrl: string
  pageIndex: number
  pageCount: number
  queuedAt: string
}

const STORAGE_KEY = "scanarr:offline_progress_queue"
let activeFlush: Promise<void> | undefined

export async function enqueueProgressUpdate(entry: Omit<ProgressQueueEntry, "queuedAt">): Promise<boolean> {
  const queue = readQueue()

  // Keep only the newest entry per chapter progress endpoint.
  const deduped = queue.filter((item) => item.progressUrl !== entry.progressUrl)
  deduped.push({
    ...entry,
    queuedAt: new Date().toISOString()
  })

  return writeQueue(deduped)
}

export async function flushQueuedProgress(csrfToken: string): Promise<void> {
  if (activeFlush) {
    await activeFlush
    return flushQueuedProgress(csrfToken)
  }

  activeFlush = sendQueuedProgress(csrfToken)
  try {
    await activeFlush
  } finally {
    activeFlush = undefined
  }
}

async function sendQueuedProgress(csrfToken: string): Promise<void> {
  const queue = readQueue()
  if (queue.length === 0) return

  for (const entry of queue) {
    try {
      const response = await fetch(entry.progressUrl, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({
          page_index: entry.pageIndex,
          page_count: entry.pageCount
        }),
        credentials: "same-origin",
        keepalive: true
      })

      if (response.ok) {
        // A new page may have been queued while this request was in flight.
        // Remove only the snapshot that was acknowledged by the server.
        writeQueue(readQueue().filter((current) => JSON.stringify(current) !== JSON.stringify(entry)))
      }
    } catch {
      // Keep this entry for the next connection or reader visit.
    }
  }
}

function readQueue(): ProgressQueueEntry[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? (parsed as ProgressQueueEntry[]) : []
  } catch {
    return []
  }
}

function writeQueue(entries: ProgressQueueEntry[]): boolean {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(entries))
    return true
  } catch {
    // Ignore quota/storage errors. Queueing is best-effort only.
    return false
  }
}
