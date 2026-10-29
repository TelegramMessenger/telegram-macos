import AppKit
import TGUIKit

func runEmptySearchChecks(_ header: ChatSearchHeader) {
  check(!header.testButtons[0].isEnabled, "Empty search enables Previous before its first response")
  check(!header.testButtons[1].isEnabled, "Empty search enables Next before its first response")
  header.updateLocalizationAndTheme(theme: theme)
  check(!header.testButtons[0].isEnabled, "Empty search enables Previous after a theme refresh")
  check(!header.testButtons[1].isEnabled, "Empty search enables Next after a theme refresh")
  let field = ChatSearchView(frame: NSMakeRect(0, 0, 480, 30))
  check(field.rightAccessory.isHidden, "Empty search exposes Clear before focus")
  field.change(state: .Focus, false)
  check(field.rightAccessory.isHidden, "Empty search exposes Clear when focused")
  field.isLoading = true
  field.isLoading = false
  check(field.rightAccessory.isHidden, "Empty search exposes Clear after loading")
  field.setString("stories")
  check(!field.rightAccessory.isHidden, "Empty search hides Clear for a nonempty query")
  field.isLoading = true
  check(field.rightAccessory.isHidden, "Empty search exposes Clear while loading")
  field.isLoading = false
  check(!field.rightAccessory.isHidden, "Empty search does not restore Clear after loading")
  field.countValue = (1, 3)
  check(!field.rightAccessory.isHidden, "Empty search hides the result count")
  field.setString("")
  field.countValue = (0, 0)
  check(field.rightAccessory.isHidden, "Empty search exposes Clear after removing the query")
  field.tokenState = .from(query: "", complete: false)
  check(!field.rightAccessory.isHidden, "Empty search hides Clear for a sender filter")
  field.tokenState = .none
  check(field.rightAccessory.isHidden, "Empty search exposes Clear after removing the sender filter")
  field.tokenState = .emojiTag(tag: .init())
  check(!field.rightAccessory.isHidden, "Empty search hides Clear for a Saved Messages tag")
  field.tokenState = .none
  field.updateLocalizationAndTheme(theme: theme)
  check(field.rightAccessory.isHidden, "Empty search exposes Clear after a theme refresh")
  let standard = SearchView(frame: field.frame)
  standard.change(state: .Focus, false)
  standard.isLoading = true
  standard.isLoading = false
  check(!standard.rightAccessory.isHidden, "Generic search lost its default clear-button behavior")
  standard.updateClearVisibility(false)
  standard.isLoading = true
  standard.isLoading = false
  check(standard.rightAccessory.isHidden, "Generic search ignores explicit clear-button visibility")
}
