# CSS Cleanup Plan - Issue 666

## Issues Identified
1. Missing `.no-print` CSS class (used in Perl modules but not defined)
2. Missing `.top-border` CSS class (used in listrecords.pm but not defined)
3. Unused `.menu-close` CSS class (defined in menu.css but not referenced anywhere)

## Proposed Solution

### Step 1: Add Missing .no-print Class
- **Location**: static/base.css (appropriate for global utility class)
- **Definition**: `.no-print { display: none !important; }`
- **Rationale**: Used across multiple Perl modules (persons.pm, brews.pm, locations.pm, etc.) to hide elements when printing

### Step 2: Add Missing .top-border Class  
- **Location**: static/layout.css (appropriate for table/styling related class)
- **Definition**: `.top-border { border-top: 2px solid white; }`
- **Rationale**: Used in listrecords.pm line 113 and 312 for table row styling

### Step 3: Remove Unused .menu-close Class
- **Location**: static/menu.css
- **Action**: Delete the `.menu-close` and `.menu-close:hover` rule sets
- **Lines to remove**: Approximately lines 72-84 in menu.css
- **Verification**: Confirmed no references in JavaScript or Perl code

## Implementation Steps

### 1. Backup Current State
```bash
cp static/base.css static/base.css.bak
cp static/layout.css static/layout.css.bak  
cp static/menu.css static/menu.css.bak
```

### 2. Add .no-print to base.css
```css
/* Add to static/base.css, perhaps near other utility classes */
/* Utility classes */
.no-print { display: none !important; }
```

### 3. Add .top-border to layout.css
```css
/* Add to static/layout.css, near existing .top-border usage in comments */
/* Table head inputs for filtering and sorting */
.top-border { border-top: 2px solid white; }
```

### 4. Remove .menu-close from menu.css
```css
/* Delete these lines from static/menu.css */
/* 
#menu .menu-close {
  display: block;
  margin-bottom: 1em;
  background: transparent;
  border: none;
  color: inherit;
  font-size: 1.5em;
  cursor: pointer;
}

#menu .menu-close:hover {
  color: var(--menu-current);
}
*/
```

### 5. Verify Changes
```bash
# Check for syntax errors in CSS files (basic validation)
# Manual verification: ensure no regressions in affected areas
# Test: 
#   - Print preview should hide .no-print elements
#   - List records should show proper top borders
#   - Menu functionality should remain intact (close functionality handled via JS)
```

## Files to Modify
- static/base.css - Add .no-print definition
- static/layout.css - Add .top-border definition  
- static/menu.css - Remove .menu-close definition

## Risk Assessment
- **Low risk**: All changes are additive (except removal of unused class)
- **No-print**: Standard utility pattern, unlikely to conflict
- **Top-border**: Matches existing usage pattern in code
- **Menu-close removal**: Verified unused via code search

## Testing Recommendations
1. Verify list views show proper top borders between sections
2. Test print preview hides elements marked with no-print class
3. Confirm menu open/close functionality still works (handled via JavaScript class toggling)
4. Check no visual regressions in browser

## Estimated Effort
- 15-20 minutes for implementation and verification