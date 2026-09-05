import { Application } from "@hotwired/stimulus"
import { afterEach, expect, it, vi } from "vitest"
import SourceReplacementController from "../../../app/javascript/controllers/source_replacement_controller"

let application: Application
const tick = () => new Promise(resolve => setTimeout(resolve, 0))
const response = (id: number, html = `Matches ${id}`, failed = false) => ({
  ok: true, redirected: false,
  text: async () => `<div data-source-matches="${id}" data-source-error="${failed}" data-match-count="${failed ? 0 : 1}">${html}</div>`
})

async function mount(count = 4) {
  document.body.innerHTML = `<div data-controller="source-replacement">
    <select data-source-replacement-target="filter" data-action="change->source-replacement#filter"><option value="">All</option><option value="2">Second</option></select>
    <p data-source-replacement-target="status" aria-live="polite"></p>
    ${Array.from({ length: count }, (_, index) => `<section data-source-replacement-target="provider" data-source-id="${index + 1}" data-source-url="/replace?to_source_id=${index + 1}&matches_only=1">
      <div data-provider-content>Waiting</div><button hidden data-provider-retry data-action="source-replacement#retry">Retry</button>
    </section>`).join("")}
  </div>`
  application = Application.start()
  application.register("source-replacement", SourceReplacementController)
  await tick()
  return document.querySelector<HTMLElement>('[data-controller="source-replacement"]')!
}

const providers = () => Array.from(document.querySelectorAll<HTMLElement>("section"))

afterEach(async () => {
  vi.useRealTimers()
  document.body.innerHTML = ""
  await tick()
  application?.stop()
  vi.unstubAllGlobals()
})

it("caps requests at three, continues the queue, and uses each provider URL", async () => {
  const pending: Array<(value: ReturnType<typeof response>) => void> = []
  const fetcher = vi.fn((_url: string, _options: RequestInit) => new Promise(resolve => pending.push(resolve)))
  vi.stubGlobal("fetch", fetcher)
  await mount()
  expect(fetcher).toHaveBeenCalledTimes(3)
  pending[0](response(1))
  await tick()
  expect(fetcher).toHaveBeenCalledTimes(4)
  expect(fetcher.mock.calls.map(call => new URL(String(call[0])).searchParams.get("to_source_id"))).toEqual(["1", "2", "3", "4"])
  pending[1](response(2))
  pending[2](response(3))
  pending[3](response(4))
  await tick()
  expect(providers().every(provider => provider.dataset.loaded === "true")).toBe(true)
  expect(document.querySelector("p")?.textContent).toBe("Checked 4 of 4 sources.")
})

it("filters already loaded groups without repeating requests", async () => {
  const fetcher = vi.fn(async (url: string) => response(Number(new URL(url).searchParams.get("to_source_id"))))
  vi.stubGlobal("fetch", fetcher)
  await mount(2)
  const filter = document.querySelector("select")!
  filter.value = "2"
  filter.dispatchEvent(new Event("change", { bubbles: true }))
  expect(providers().map(provider => provider.hidden)).toEqual([true, false])
  expect(fetcher).toHaveBeenCalledTimes(2)
})

it("aborts on disconnect and ignores stale responses after reconnect", async () => {
  const pending: Array<(value: ReturnType<typeof response>) => void> = []
  const signals: AbortSignal[] = []
  const fetcher = vi.fn((_url: string, options: RequestInit) => {
    signals.push(options.signal as AbortSignal)
    return new Promise(resolve => pending.push(resolve))
  })
  vi.stubGlobal("fetch", fetcher)
  const root = await mount(4)
  root.remove()
  await tick()
  expect(signals.every(signal => signal.aborted)).toBe(true)
  document.body.append(root)
  await tick()
  expect(fetcher).toHaveBeenCalledTimes(6)
  pending[0](response(1, "Stale matches"))
  await tick()
  expect(root.textContent).not.toContain("Stale matches")
  expect(fetcher).toHaveBeenCalledTimes(6)
  pending[3](response(1, "Fresh matches"))
  await tick()
  expect(root.textContent).toContain("Fresh matches")
  expect(fetcher).toHaveBeenCalledTimes(7)
})

it("does not insert a login page and allows a failed source to retry", async () => {
  const fetcher = vi.fn()
    .mockResolvedValueOnce({ ok: true, redirected: false, text: async () => "<form>Private login page</form>" })
    .mockResolvedValueOnce(response(1))
  vi.stubGlobal("fetch", fetcher)
  await mount(1)
  expect(document.body.textContent).not.toContain("Private login page")
  expect(providers()[0].dataset.failed).toBe("true")
  const retry = document.querySelector<HTMLButtonElement>("[data-provider-retry]")!
  expect(retry.hidden).toBe(false)
  retry.click()
  await tick()
  expect(fetcher).toHaveBeenCalledTimes(2)
  expect(providers()[0].dataset.loaded).toBe("true")
  expect(retry.hidden).toBe(true)
})

it("shows retry for server-reported errors without repeatedly requesting them", async () => {
  const fetcher = vi.fn().mockResolvedValue(response(1, "Provider unavailable", true))
  vi.stubGlobal("fetch", fetcher)
  await mount(1)
  expect(providers()[0].dataset.failed).toBe("true")
  expect(document.querySelector<HTMLButtonElement>("[data-provider-retry]")!.hidden).toBe(false)
  expect(document.body.textContent).toContain("Provider unavailable")
  expect(fetcher).toHaveBeenCalledTimes(1)
})

it("skips successfully loaded providers after reconnect", async () => {
  const fetcher = vi.fn().mockResolvedValue(response(1))
  vi.stubGlobal("fetch", fetcher)
  const root = await mount(1)
  root.remove()
  await tick()
  document.body.append(root)
  await tick()
  expect(fetcher).toHaveBeenCalledTimes(1)
})

it.each([
  { ok: true, redirected: true },
  { ok: false, redirected: false }
])("rejects redirected or unsuccessful responses", async flags => {
  const text = vi.fn(async () => "<div data-source-matches=\"1\">Untrusted response</div>")
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ...flags, text }))
  await mount(1)
  expect(text).not.toHaveBeenCalled()
  expect(document.body.textContent).not.toContain("Untrusted response")
  expect(providers()[0].dataset.failed).toBe("true")
})

it("times out stalled requests, offers retry, and frees the queue slots", async () => {
  vi.useFakeTimers()
  const signals: AbortSignal[] = []
  const fetcher = vi.fn((_url: string, options: RequestInit) => {
    signals.push(options.signal as AbortSignal)
    return new Promise(() => {})
  })
  vi.stubGlobal("fetch", fetcher)
  const mounted = mount(4)
  await vi.advanceTimersByTimeAsync(0)
  await mounted
  expect(fetcher).toHaveBeenCalledTimes(3)

  await vi.advanceTimersByTimeAsync(15_001)

  expect(fetcher).toHaveBeenCalledTimes(4)
  expect(signals.slice(0, 3).every(signal => signal.aborted)).toBe(true)
  expect(signals[3].aborted).toBe(false)
  expect(providers()[0].dataset.failed).toBe("true")
  expect(providers()[0].hasAttribute("aria-busy")).toBe(false)
  expect(providers()[0].querySelector<HTMLButtonElement>("[data-provider-retry]")!.hidden).toBe(false)
})

it("moves useful matches above checks and promotes a failed source after retry", async () => {
  const pending: Array<(value: ReturnType<typeof response>) => void> = []
  const fetcher = vi.fn(() => new Promise(resolve => pending.push(resolve)))
  vi.stubGlobal("fetch", fetcher)
  const root = await mount(2)
  const matches = document.createElement("div")
  matches.dataset.sourceReplacementTarget = "matches"
  const details = document.createElement("details")
  details.dataset.providerChecks = ""
  const checks = document.createElement("div")
  checks.dataset.sourceReplacementTarget = "checks"
  details.append(checks)
  root.append(matches, details)
  await tick()

  pending[0](response(1, "Useful match"))
  pending[1](response(2, "Unavailable", true))
  await tick()
  expect(matches.querySelector("section")?.dataset.sourceId).toBe("1")
  expect(checks.querySelector("section")?.dataset.sourceId).toBe("2")
  expect(details.open).toBe(false)

  const filter = root.querySelector("select")!
  filter.value = "2"
  filter.dispatchEvent(new Event("change", { bubbles: true }))
  expect(details.open).toBe(true)
  checks.querySelector<HTMLButtonElement>("[data-provider-retry]")!.click()
  pending[2](response(2, "Recovered match"))
  await tick()
  expect(Array.from(matches.querySelectorAll("section"), section => section.dataset.sourceId)).toEqual(["1", "2"])
  expect(checks.querySelector("section")).toBeNull()
})

it("explains when completed source checks found no matches", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
    ok: true, redirected: false,
    text: async () => '<div data-source-matches="1" data-match-count="0">No results</div>'
  }))
  await mount(1)
  expect(document.querySelector("p")?.textContent).toContain("No matches found. Try another title.")
})
