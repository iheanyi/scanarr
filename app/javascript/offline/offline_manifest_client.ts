export interface OfflinePage {
  index: number
  source: string
  url: string
}

export interface OfflinePagesPayload {
  chapter_public_id: string
  chapter_number: string
  status: string
  page_count: number
  pages: OfflinePage[]
}

export interface OfflineManifestEntryPayload {
  chapter_public_id: string
  status: string
  last_synced_at?: string
  last_error?: string
}

export async function pinChapter(pinUrl: string, csrfToken: string): Promise<void> {
  await jsonRequest(pinUrl, {
    method: "POST",
    headers: csrfHeaders(csrfToken)
  })
}

export async function unpinChapter(unpinUrl: string, csrfToken: string): Promise<void> {
  await jsonRequest(unpinUrl, {
    method: "DELETE",
    headers: csrfHeaders(csrfToken)
  })
}

export async function fetchOfflinePages(pagesUrl: string): Promise<OfflinePagesPayload> {
  return await jsonRequest(pagesUrl, {
    method: "GET",
    headers: { Accept: "application/json" }
  })
}

export async function syncOfflineManifest(
  manifestUrl: string,
  entries: OfflineManifestEntryPayload[],
  csrfToken: string
): Promise<void> {
  await jsonRequest(manifestUrl, {
    method: "PATCH",
    headers: csrfHeaders(csrfToken),
    body: JSON.stringify({ entries })
  })
}

function csrfHeaders(csrfToken: string): HeadersInit {
  return {
    "Content-Type": "application/json",
    Accept: "application/json",
    "X-CSRF-Token": csrfToken
  }
}

async function jsonRequest<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, credentials: "same-origin" })
  const payload = await response.json().catch(() => ({}))

  if (!response.ok) {
    const message = typeof payload?.error === "string" ? payload.error : `Request failed (${response.status})`
    throw new Error(message)
  }

  return payload as T
}
