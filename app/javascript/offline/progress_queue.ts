interface ProgressQueueEntry {
  progressUrl: string
  pageIndex: number
  pageCount: number
  queuedAt: string
}

const STORAGE_KEY = "scanarr:offline_progress_queue"

export async function enqueueProgressUpdate(entry: Omit<ProgressQueueEntry, "queuedAt">): Promise<void> {
  const queue = readQueue()

  // Keep only the newest entry per chapter progress endpoint.
  const deduped = queue.filter((item) => item.progressUrl !== entry.progressUrl)
  deduped.push({
    ...entry,
    queuedAt: new Date().toISOString()
  })

  writeQueue(deduped)
}

export async function flushQueuedProgress(csrfToken: string): Promise<void> {
  const queue = readQueue()
  if (queue.length === 0) return

  const failed: ProgressQueueEntry[] = []

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
        credentials: "same-origin"
      })

      if (!response.ok) failed.push(entry)
    } catch {
      failed.push(entry)
    }
  }

  writeQueue(failed)
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

function writeQueue(entries: ProgressQueueEntry[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(entries))
  } catch {
    // Ignore quota/storage errors. Queueing is best-effort only.
  }
}
