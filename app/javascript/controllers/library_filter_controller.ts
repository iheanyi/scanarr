import { Controller } from "@hotwired/stimulus"

type FrameRenderEvent = CustomEvent<{
  render: (current: Element, incoming: Element) => void | Promise<void>
}>

export default class extends Controller {
  preserveFocus(event: FrameRenderEvent) {
    const active = document.activeElement
    if (!(active instanceof HTMLInputElement) || active.type !== "search") return
    if (!(event.target instanceof Element) || !event.target.contains(active)) return

    const name = active.name
    const start = active.selectionStart
    const end = active.selectionEnd
    const render = event.detail.render

    event.detail.render = async (current, incoming) => {
      await render(current, incoming)
      const replacement = Array.from(current.querySelectorAll<HTMLInputElement>('input[type="search"]'))
        .find(input => input.name === name)
      replacement?.focus({ preventScroll: true })
      if (start !== null && end !== null) replacement?.setSelectionRange(start, end)
    }
  }
}
