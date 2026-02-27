import { Controller } from "@hotwired/stimulus"
import {
  getAllOfflineChapters,
  type OfflineChapterRecord
} from "../offline/idb_store"

interface SeriesGroup {
  seriesSlug: string
  sourceSlug: string
  chapters: OfflineChapterRecord[]
}

export default class extends Controller {
  static targets = ["list", "empty", "count"]

  declare readonly listTarget: HTMLElement
  declare readonly emptyTarget: HTMLElement
  declare readonly countTarget: HTMLElement
  declare readonly hasListTarget: boolean
  declare readonly hasEmptyTarget: boolean
  declare readonly hasCountTarget: boolean

  connect() {
    void this.render()
  }

  async render() {
    const allChapters = await getAllOfflineChapters()
    const complete = allChapters.filter((ch) => ch.status === "complete")

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${complete.length} chapter${complete.length !== 1 ? "s" : ""}`
    }

    if (complete.length === 0) {
      if (this.hasEmptyTarget) this.emptyTarget.hidden = false
      if (this.hasListTarget) this.listTarget.hidden = true
      return
    }

    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    if (this.hasListTarget) this.listTarget.hidden = false

    const groups = this.groupBySeries(complete)
    if (this.hasListTarget) {
      this.listTarget.innerHTML = groups.map((g) => this.renderSeriesCard(g)).join("")
    }
  }

  private groupBySeries(chapters: OfflineChapterRecord[]): SeriesGroup[] {
    const map = new Map<string, SeriesGroup>()

    for (const ch of chapters) {
      const key = `${ch.sourceSlug}:${ch.seriesSlug}`
      let group = map.get(key)
      if (!group) {
        group = { seriesSlug: ch.seriesSlug, sourceSlug: ch.sourceSlug, chapters: [] }
        map.set(key, group)
      }
      group.chapters.push(ch)
    }

    for (const group of map.values()) {
      group.chapters.sort((a, b) => {
        const numA = parseFloat(a.chapterIdentifier) || 0
        const numB = parseFloat(b.chapterIdentifier) || 0
        return numA - numB
      })
    }

    return Array.from(map.values()).sort((a, b) =>
      a.seriesSlug.localeCompare(b.seriesSlug)
    )
  }

  private renderSeriesCard(group: SeriesGroup): string {
    const title = this.slugToTitle(group.seriesSlug)
    const chapterCount = group.chapters.length
    const seriesUrl = `/library/${group.seriesSlug}`

    const chapterList = group.chapters.map((ch) => {
      const readUrl = `/sources/${ch.sourceSlug}/${ch.seriesSlug}/chapters/${ch.chapterIdentifier}`
      const label = `Ch. ${ch.chapterIdentifier}`
      const pages = ch.pageCount > 0 ? `${ch.pageCount} pages` : ""

      return `<a href="${this.escapeHtml(readUrl)}"
                 class="flex items-center justify-between rounded-md px-3 py-2 text-sm transition-colors hover:bg-surface-2/60"
                 data-turbo-preload="">
                <span class="font-medium text-foreground">${this.escapeHtml(label)}</span>
                <span class="text-xs text-muted">${this.escapeHtml(pages)}</span>
              </a>`
    }).join("")

    return `<div class="rounded-xl border border-border bg-surface/40 overflow-hidden">
              <a href="${this.escapeHtml(seriesUrl)}"
                 class="flex items-center justify-between gap-3 border-b border-border px-4 py-3 transition-colors hover:bg-surface-2/40"
                 data-turbo-preload="">
                <div class="min-w-0">
                  <h3 class="text-base font-semibold text-foreground truncate">${this.escapeHtml(title)}</h3>
                  <p class="text-xs text-muted mt-0.5">${chapterCount} chapter${chapterCount !== 1 ? "s" : ""} available offline</p>
                </div>
                <svg class="h-4 w-4 shrink-0 text-muted" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>
              </a>
              <div class="divide-y divide-border/50">
                ${chapterList}
              </div>
            </div>`
  }

  private slugToTitle(slug: string): string {
    return slug
      .replace(/^[a-z0-9]+-/, "")
      .replace(/-/g, " ")
      .replace(/\b\w/g, (c) => c.toUpperCase())
  }

  private escapeHtml(text: string): string {
    const el = document.createElement("span")
    el.textContent = text
    return el.innerHTML
  }
}
