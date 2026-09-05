import { Application } from "@hotwired/stimulus"
import { afterEach, expect, it } from "vitest"
import LibraryFilterController from "../../../app/javascript/controllers/library_filter_controller"

let application: Application

afterEach(() => {
  application?.stop()
  document.body.innerHTML = ""
})

it("keeps search focus and cursor when the filter frame replaces controls", async () => {
  document.body.innerHTML = `<div data-controller="library-filter" data-action="turbo:before-frame-render->library-filter#preserveFocus">
    <turbo-frame id="library-content"><input type="search" name="q" value="One Piece"></turbo-frame>
  </div>`
  application = Application.start()
  application.register("library-filter", LibraryFilterController)
  await new Promise(resolve => setTimeout(resolve, 0))

  const frame = document.querySelector("turbo-frame")!
  const input = frame.querySelector("input")!
  input.focus()
  input.setSelectionRange(3, 3)
  const incoming = frame.cloneNode(true) as Element
  const detail = { render: async (current: Element, replacement: Element) => { current.innerHTML = replacement.innerHTML } }
  frame.dispatchEvent(new CustomEvent("turbo:before-frame-render", { bubbles: true, detail }))
  await detail.render(frame, incoming)

  const replacement = frame.querySelector("input")!
  expect(replacement).not.toBe(input)
  expect(document.activeElement).toBe(replacement)
  expect(replacement.selectionStart).toBe(3)
  expect(replacement.value).toBe("One Piece")
})
