import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["provider", "status", "filter", "matches", "checks"]

  declare providerTargets: HTMLElement[]
  declare statusTarget: HTMLElement
  declare hasStatusTarget: boolean
  declare filterTarget: HTMLSelectElement
  declare hasFilterTarget: boolean
  declare matchesTarget: HTMLElement
  declare hasMatchesTarget: boolean
  declare checksTarget: HTMLElement
  declare hasChecksTarget: boolean

  private generation = 0
  private queue: HTMLElement[] = []
  private active = new Map<HTMLElement, AbortController>()

  connect() {
    this.generation += 1
    this.active = new Map()
    this.queue = this.providerTargets.filter(provider => provider.dataset.loaded !== "true")
    this.queue.forEach(provider => { delete provider.dataset.failed })
    this.filter()
    this.pump(this.generation)
  }

  disconnect() {
    this.generation += 1
    this.queue = []
    this.active.forEach((request, provider) => {
      provider.removeAttribute("aria-busy")
      request.abort()
    })
    this.active.clear()
  }

  filter() {
    const selected = this.hasFilterTarget ? this.filterTarget.value : ""
    this.providerTargets.forEach(provider => {
      provider.hidden = !!selected && provider.dataset.sourceId !== selected
      if (selected && !provider.hidden) {
        const checks = provider.closest<HTMLDetailsElement>("details[data-provider-checks]")
        if (checks) checks.open = true
      }
    })
  }

  retry(event: Event) {
    event.preventDefault()
    const provider = (event.target as Element).closest<HTMLElement>('[data-source-replacement-target~="provider"]')
    if (!provider || !this.element.contains(provider) || this.active.has(provider) || this.queue.includes(provider)) return

    delete provider.dataset.loaded
    delete provider.dataset.failed
    this.queue.push(provider)
    this.pump(this.generation)
  }

  private pump(generation: number) {
    if (generation !== this.generation || !this.element.isConnected) return
    while (this.active.size < 3 && this.queue.length) {
      const provider = this.queue.shift()!
      const request = new AbortController()
      this.active.set(provider, request)
      delete provider.dataset.failed
      provider.setAttribute("aria-busy", "true")
      this.load(provider, request, generation)
    }
    this.updateStatus()
  }

  private async load(provider: HTMLElement, request: AbortController, generation: number) {
    let timeout: number | undefined
    try {
      const deadline = new Promise<never>((_resolve, reject) => {
        request.signal.addEventListener("abort", () => reject(new Error("Source lookup aborted")), { once: true })
        timeout = window.setTimeout(() => {
          request.abort()
          reject(new Error("Source lookup timed out"))
        }, 15_000)
      })
      const html = await Promise.race([this.fetchMarkup(provider, request), deadline])
      if (!this.isCurrent(generation)) return

      const parsed = new DOMParser().parseFromString(html, "text/html")
      const matches = Array.from(parsed.querySelectorAll<HTMLElement>("[data-source-matches]"))
        .find(element => element.dataset.sourceMatches === provider.dataset.sourceId)
      const content = provider.querySelector<HTMLElement>("[data-provider-content]")
      if (!matches || !content) throw new Error("Unexpected source response")

      content.innerHTML = matches.innerHTML
      const failed = matches.dataset.sourceError === "true"
      provider.dataset.loaded = failed ? "false" : "true"
      if (failed) provider.dataset.failed = "true"
      else delete provider.dataset.failed
      const retry = this.retryButton(provider)
      if (retry) retry.hidden = !failed
      const count = failed ? 0 : Math.max(0, Number(matches.dataset.matchCount) || 0)
      this.placeProvider(provider, count)
    } catch {
      if (!this.isCurrent(generation)) return
      provider.dataset.failed = "true"
      this.placeProvider(provider, 0)
      const content = provider.querySelector<HTMLElement>("[data-provider-content]")
      if (content) {
        content.textContent = "Could not check this source. Try again in a moment."
        let retry = this.retryButton(provider)
        if (!retry) {
          retry = document.createElement("button")
          retry.type = "button"
          retry.textContent = "Try again"
          retry.dataset.action = "source-replacement#retry"
          retry.className = "mt-3 underline underline-offset-4"
          content.append(retry)
        }
        retry.hidden = false
      }
    } finally {
      window.clearTimeout(timeout)
      if (this.isCurrent(generation)) {
        provider.removeAttribute("aria-busy")
        this.active.delete(provider)
        this.pump(generation)
      }
    }
  }

  private async fetchMarkup(provider: HTMLElement, request: AbortController) {
    const url = new URL(provider.dataset.sourceUrl || "", window.location.href)
    if (!provider.dataset.sourceUrl || url.origin !== window.location.origin) throw new Error("Invalid source lookup URL")
    const response = await fetch(url.href, { signal: request.signal, headers: { Accept: "text/html" }, credentials: "same-origin", cache: "no-store" })
    if (!response.ok || response.redirected) throw new Error("Source lookup failed")
    return response.text()
  }

  private isCurrent(generation: number) {
    return generation === this.generation && this.element.isConnected
  }

  private retryButton(provider: HTMLElement) {
    return provider.querySelector<HTMLButtonElement>('button[data-action*="source-replacement#retry"]')
  }

  private placeProvider(provider: HTMLElement, count: number) {
    provider.dataset.matchCount = String(count)
    const destination = count > 0
      ? (this.hasMatchesTarget ? this.matchesTarget : null)
      : (this.hasChecksTarget ? this.checksTarget : null)
    if (destination && provider.parentElement !== destination) destination.append(provider)
    this.filter()
  }

  private updateStatus() {
    if (!this.hasStatusTarget) return
    const total = this.providerTargets.length
    const checked = this.providerTargets.filter(provider => provider.dataset.loaded === "true" || provider.dataset.failed === "true").length
    const pending = this.active.size || this.queue.length
    const matches = this.providerTargets.reduce((sum, provider) => sum + (Number(provider.dataset.matchCount) || 0), 0)
    const failed = this.providerTargets.some(provider => provider.dataset.failed === "true")
    const summary = `Checked ${checked} of ${total} sources.`
    this.statusTarget.textContent = pending
      ? `${summary} Checking for matches…`
      : matches > 0 ? summary
      : `${summary} ${failed ? "No matches found yet. Retry unavailable sources or try another title." : "No matches found. Try another title."}`
  }
}
