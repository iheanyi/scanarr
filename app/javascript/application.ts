// Entry point for the build script in package.json
import { Turbo } from "@hotwired/turbo-rails"
import TurboPower from "turbo_power"
import "./controllers"

TurboPower.initialize(Turbo.StreamActions)

// Clean up ephemeral UI state before Turbo caches the page.
// Prevents stale dropdowns/modals from appearing on back navigation.
document.addEventListener("turbo:before-cache", () => {
  // Close open dropdowns
  document.querySelectorAll<HTMLElement>("[data-dropdown-target='menu']:not(.hidden)").forEach(el => {
    el.classList.add("hidden")
  })
  // Close open dialogs
  document.querySelectorAll<HTMLDialogElement>("dialog[open]").forEach(d => {
    d.close()
  })
  // Reset flash messages (they have data-turbo-temporary, but be safe)
  document.querySelectorAll<HTMLElement>("[data-controller='flash-dismiss']").forEach(el => {
    el.remove()
  })
})
