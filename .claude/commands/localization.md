# Automated Localization Command

Process all `//TODOLANG` markers in Swift files and convert inline string literals into localized strings.

## Instructions

### 1. Discovery
Find all `//TODOLANG` markers recursively in Swift files (Telegram-Mac/*). For each marker, capture the line itself plus 2 lines above and 2 lines below for context.

### 2. Generate Localization Key Prefix

Use this priority order:

1. **File name** (primary): `StarGiftOfferView.swift` → `StarGift.OfferView`
2. **Primary type name** (secondary): `class StarGiftItemController` → `StarGift.ItemController`
3. **Existing namespaces in code** (tertiary): If file references `StarGift.ModelBuilder.*` → use `StarGift.ModelBuilder`

### 3. Generate Key Suffix

- Remove variables from the string
- Use concise PascalCase
- Focus on semantic meaning
- Avoid unnecessary words like "Message", "Text"

Example: `"You accepted the offer"` → `StarGift.OfferView.AcceptedOffer`

### 4. Parameter Replacement

Convert Swift interpolation to ordered `.strings` placeholders:

| Swift | .strings |
|-------|----------|
| `\(intValue)` | `%1$d` |
| `\(stringValue)` | `%1$@` |

Keep insertion order deterministic (1 = first variable, 2 = second, etc.). Input for intValue is always Int type in swift, so convert param to Int if needed.

**Percentage Values:** If the string contains a percentage (%), always use a string placeholder (`%1$@`) and pass the complete value with the percent sign from Swift (e.g., `"\(value)%"`). Never use `%1$d%%` format.

Example:
```
"10% chance to win"
```
becomes:
```
"Key" = "%1$@ chance to win";
strings().key("\(percent)%")
```

Example:
```
"You paid \(amount) to \(authorName)"
```
becomes:
```
"StarGift.OfferView.PaymentInfo" = "You paid %1$@ to %2$@";
```

### 5. Plural/Countable Strings

If the string involves a count (int value), ALWAYS generate both the `_one` and `_other` variants, with `_one` placed directly above `_other`. Never write `_other` alone: the translation platform shows a missing `_one` as an empty (one) form and translators skip the key.

```
"Key_one" = "%1$d item selected";
"Key_other" = "%1$d items selected";
```

The generated Swift function will always take an `Int` parameter for plural selection and is named after the `_other` key. If the string has no `%d` placeholder but still needs plural selection, pass the count anyway - it will be used for form selection but won't appear in the output:

```
"Key_one" = "Item selected";
"Key_other" = "Items selected";
```

Usage: `strings().keyOther(count)` - the count determines plural form even if not displayed.

### 6. Write to Localizable.strings

- File: `Telegram-Mac/en.lproj/Localizable.strings`
- Append new keys
- Keep file sorted alphabetically
- No duplicates
- Exact format: `"Namespace.Key" = "Value";`

### 7. Replace Swift Code

Replace ONLY the string literal, preserving all formatting:

**Before:**
```swift
//TODOLANG
text = "Your offer \(amount.fullyFormatted) for \(authorName)'s gift \(giftString) was accepted"
```

**After:**
```swift
text = strings().starGiftOfferViewAcceptedOffer(amount.fullyFormatted, authorName, giftString)
```

**Critical:** No indentation changes, no line breaks, no whitespace modifications.

### 8. Run SwiftGen

After updating Localizable.strings, execute:

```bash
swiftgen strings -p ./tools/strings.stencil \
  --output ./packages/Localization/Sources/Localization/Localizable.swift \
  ./Telegram-Mac/en.lproj/Localizable.strings
```

Report the command output.

### 9. Validation

Ensure:
- SwiftGen output compiles
- Correct number of parameters in each rewritten call
- All `.strings` entries use ordered format specifiers
- Prefixes follow inference rules
- No duplicate keys

## Do NOT

- Reformat Swift code
- Change indentation, layout, or whitespace
- Modify unrelated strings
- Change logic or introduce new variables
- Add trailing spaces or blank lines in .strings file

## Arguments

$ARGUMENTS

If arguments are provided, limit processing to the specified file(s). Otherwise, process all files with `//TODOLANG` markers.
