export type OfflineChapterStatus = "queued" | "downloading" | "complete" | "failed" | "pinned"

export interface OfflineChapterRecord {
  chapterKey: string
  chapterPublicId: string
  sourceSlug: string
  seriesSlug: string
  chapterIdentifier: string
  status: OfflineChapterStatus
  pageCount: number
  downloadedCount: number
  pages: string[]
  updatedAt: string
  lastError?: string
}

const DB_NAME = "scanarr-offline"
const DB_VERSION = 1
const CHAPTERS_STORE = "offline_chapters"

let dbPromise: Promise<IDBDatabase> | null = null

function requestToPromise<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

function openDatabase(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise

  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION)

    request.onupgradeneeded = () => {
      const db = request.result
      if (!db.objectStoreNames.contains(CHAPTERS_STORE)) {
        const store = db.createObjectStore(CHAPTERS_STORE, { keyPath: "chapterKey" })
        store.createIndex("status", "status", { unique: false })
        store.createIndex("updatedAt", "updatedAt", { unique: false })
      }
    }

    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })

  return dbPromise
}

export async function getOfflineChapter(chapterKey: string): Promise<OfflineChapterRecord | null> {
  const db = await openDatabase()
  const tx = db.transaction(CHAPTERS_STORE, "readonly")
  const store = tx.objectStore(CHAPTERS_STORE)
  const record = await requestToPromise(store.get(chapterKey))
  return (record as OfflineChapterRecord | undefined) || null
}

export async function putOfflineChapter(record: OfflineChapterRecord): Promise<void> {
  const db = await openDatabase()
  const tx = db.transaction(CHAPTERS_STORE, "readwrite")
  const store = tx.objectStore(CHAPTERS_STORE)
  await requestToPromise(store.put(record))
  await transactionDone(tx)
}

export async function patchOfflineChapter(chapterKey: string, patch: Partial<OfflineChapterRecord>): Promise<OfflineChapterRecord | null> {
  const existing = await getOfflineChapter(chapterKey)
  if (!existing) return null

  const nextRecord = {
    ...existing,
    ...patch,
    updatedAt: patch.updatedAt || new Date().toISOString()
  }
  await putOfflineChapter(nextRecord)
  return nextRecord
}

export async function deleteOfflineChapter(chapterKey: string): Promise<void> {
  const db = await openDatabase()
  const tx = db.transaction(CHAPTERS_STORE, "readwrite")
  const store = tx.objectStore(CHAPTERS_STORE)
  await requestToPromise(store.delete(chapterKey))
  await transactionDone(tx)
}

function transactionDone(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error)
  })
}
